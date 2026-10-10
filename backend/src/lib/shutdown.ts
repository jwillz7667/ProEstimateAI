import type { Server } from 'http';

/**
 * Stop accepting connections, drain active HTTP requests, then release their
 * dependencies. One deadline bounds both draining and dependency cleanup.
 * Returns false on timeout so the caller can terminate with a failure status.
 */
export async function shutdownHttpServer(
  server: Server,
  cleanup: () => Promise<void>,
  timeoutMs = 30_000,
): Promise<boolean> {
  let timedOut = false;
  let timeout: ReturnType<typeof setTimeout> | undefined;

  const deadline = new Promise<boolean>((resolve) => {
    timeout = setTimeout(() => {
      timedOut = true;
      server.closeAllConnections();
      resolve(false);
    }, timeoutMs);
  });

  const shutdown = new Promise<void>((resolve, reject) => {
    // On our supported Node >=20, close also closes idle keep-alive connections.
    server.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  }).then(async () => {
    // Forced socket closure must not start cleanup after the deadline expires.
    if (timedOut) return false;
    await cleanup();
    return true;
  });

  try {
    return await Promise.race([shutdown, deadline]);
  } finally {
    clearTimeout(timeout);
  }
}
