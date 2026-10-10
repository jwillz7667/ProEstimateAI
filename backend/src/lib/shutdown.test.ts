import { once } from 'events';
import http, { type Server, type ServerResponse } from 'http';
import { setImmediate as nextTurn } from 'timers/promises';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { shutdownHttpServer } from './shutdown';

const servers: Server[] = [];
const agents: http.Agent[] = [];

async function listen(server: Server): Promise<number> {
  servers.push(server);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') {
    throw new Error('Expected a TCP server address');
  }
  return address.port;
}

function get(port: number, agent: http.Agent | false = false): Promise<string> {
  return new Promise((resolve, reject) => {
    const request = http.get({ hostname: '127.0.0.1', port, agent }, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk: string) => { body += chunk; });
      response.on('end', () => resolve(body));
      response.on('error', reject);
    });
    request.on('error', reject);
  });
}

function holdRequest(): { server: Server; received: Promise<ServerResponse> } {
  let receive: (response: ServerResponse) => void = () => {};
  const received = new Promise<ServerResponse>((resolve) => { receive = resolve; });
  const server = http.createServer((_request, response) => { receive(response); });
  return { server, received };
}

afterEach(async () => {
  for (const agent of agents.splice(0)) agent.destroy();
  await Promise.all(servers.splice(0).map((server) => new Promise<void>((resolve) => {
    server.closeAllConnections();
    server.close(() => resolve());
  })));
  vi.restoreAllMocks();
});

describe('shutdownHttpServer', () => {
  it('finishes an in-flight response before cleanup and refuses new connections', async () => {
    const { server, received } = holdRequest();
    const port = await listen(server);
    const request = get(port);
    const response = await received;
    const cleanup = vi.fn(async () => {
      expect(response.writableFinished).toBe(true);
    });

    const shutdown = shutdownHttpServer(server, cleanup, 1_000);
    await nextTurn();

    expect(server.listening).toBe(false);
    expect(cleanup).not.toHaveBeenCalled();
    await expect(get(port)).rejects.toMatchObject({ code: 'ECONNREFUSED' });

    response.end('request completed with dependencies still available');
    await expect(request).resolves.toBe('request completed with dependencies still available');
    await expect(shutdown).resolves.toBe(true);
    expect(cleanup).toHaveBeenCalledTimes(1);
  });

  it('closes idle keep-alive connections without waiting for their idle timeout', async () => {
    const server = http.createServer((_request, response) => { response.end('ok'); });
    server.keepAliveTimeout = 65_000;
    const port = await listen(server);
    const agent = new http.Agent({ keepAlive: true });
    agents.push(agent);
    await expect(get(port, agent)).resolves.toBe('ok');
    await nextTurn();
    expect(Object.values(agent.freeSockets).flat()).toHaveLength(1);

    const cleanup = vi.fn(async () => {});
    await expect(shutdownHttpServer(server, cleanup, 1_000)).resolves.toBe(true);
    expect(cleanup).toHaveBeenCalledTimes(1);
  });

  it('bounds a stalled request and does not start cleanup after forced closure', async () => {
    const { server, received } = holdRequest();
    const port = await listen(server);
    // Attach the rejection handler before the deadline destroys the socket.
    const request = get(port).catch((err: NodeJS.ErrnoException) => err);
    await received;
    const cleanup = vi.fn(async () => {});

    await expect(shutdownHttpServer(server, cleanup, 25)).resolves.toBe(false);
    await expect(request).resolves.toMatchObject({ code: 'ECONNRESET' });
    await nextTurn();
    expect(cleanup).not.toHaveBeenCalled();
  });

  it('keeps the deadline active while dependency cleanup is stalled', async () => {
    const server = http.createServer();
    await listen(server);
    let finishCleanup: () => void = () => {};
    const cleanup = vi.fn(() => new Promise<void>((resolve) => { finishCleanup = resolve; }));

    await expect(shutdownHttpServer(server, cleanup, 25)).resolves.toBe(false);
    expect(cleanup).toHaveBeenCalledTimes(1);
    finishCleanup();
  });

  it('propagates dependency cleanup failures and cancels the deadline', async () => {
    const server = http.createServer();
    await listen(server);
    const clearTimeout = vi.spyOn(globalThis, 'clearTimeout');
    const failure = new Error('Dependency disconnect failed');

    await expect(shutdownHttpServer(server, async () => { throw failure; }))
      .rejects.toBe(failure);
    expect(clearTimeout).toHaveBeenCalledTimes(1);
  });

  it('propagates server close errors without running dependency cleanup', async () => {
    const server = http.createServer();
    const cleanup = vi.fn(async () => {});

    await expect(shutdownHttpServer(server, cleanup))
      .rejects.toMatchObject({ code: 'ERR_SERVER_NOT_RUNNING' });
    expect(cleanup).not.toHaveBeenCalled();
  });
});
