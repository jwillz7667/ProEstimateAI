/**
 * Thin wrapper around the ProEstimate backend API.
 * Unwraps the `{ ok, data, error }` envelope and preserves HTTP status on
 * thrown errors so callers can distinguish a 404 from a 5xx.
 *
 * Base URL is sourced from env with a Railway production fallback. Set
 * `API_BASE_URL` (server) or `NEXT_PUBLIC_API_BASE_URL` (client) to override.
 */
export const API_BASE_URL: string =
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  process.env.API_BASE_URL ??
  "https://proestimate-api-production.up.railway.app/v1";

export interface APIEnvelope<T> {
  ok: boolean;
  data?: T;
  error?: { code: string; message: string };
  meta?: { request_id?: string; timestamp?: string };
}

export class APIError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(message: string, code: string, status: number) {
    super(message);
    this.name = "APIError";
    this.code = code;
    this.status = status;
  }
}

export async function fetchAPI<T>(
  path: string,
  init?: RequestInit
): Promise<T> {
  const url = path.startsWith("http") ? path : `${API_BASE_URL}${path}`;

  const response = await fetch(url, {
    cache: "no-store",
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...(init?.headers ?? {}),
    },
  });

  let body: APIEnvelope<T>;
  try {
    body = (await response.json()) as APIEnvelope<T>;
  } catch {
    throw new APIError(
      `Invalid JSON response (HTTP ${response.status})`,
      "INVALID_RESPONSE",
      response.status,
    );
  }

  if (!response.ok || !body.ok || body.data === undefined) {
    const code = body.error?.code ?? "API_ERROR";
    const message = body.error?.message ?? response.statusText;
    throw new APIError(message, code, response.status);
  }

  return body.data;
}
