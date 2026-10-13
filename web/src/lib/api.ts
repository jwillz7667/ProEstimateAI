/**
 * Thin wrapper around the ProEstimate backend API.
 * Unwraps the `{ ok, data, error }` envelope and preserves HTTP status on
 * thrown errors so callers can distinguish a 404 from a 5xx.
 *
 * Base URL is sourced from env with a Railway production fallback. Set
 * `API_BASE_URL` (server) or `NEXT_PUBLIC_API_BASE_URL` (client) to override.
 */
export const API_BASE_URL: string =
  (process.env.NEXT_PUBLIC_API_BASE_URL ||
    process.env.API_BASE_URL ||
    "https://proestimate-api-production-75e5.up.railway.app/v1").replace(/\/+$/, "");

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
  const url = /^https?:\/\//.test(path) ? path : `${API_BASE_URL}${path}`;
  // RequestInit accepts both objects and Headers instances. Spreading Headers
  // silently drops their entries, including authorization and custom headers.
  const headers = new Headers(init?.headers);
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  if (init?.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(url, {
    cache: "no-store",
    ...init,
    headers,
  });

  let rawBody: unknown;
  try {
    rawBody = await response.json();
  } catch {
    throw new APIError(
      `Invalid JSON response (HTTP ${response.status})`,
      "INVALID_RESPONSE",
      response.status,
    );
  }

  if (!rawBody || typeof rawBody !== "object" || !("ok" in rawBody) ||
      typeof rawBody.ok !== "boolean") {
    throw new APIError("Unable to read the server response. Please try again.", "INVALID_RESPONSE", response.status);
  }
  const body = rawBody as APIEnvelope<T>;

  if (!response.ok || !body.ok || body.data === undefined) {
    const code = typeof body.error?.code === "string" ? body.error.code : "API_ERROR";
    const message = typeof body.error?.message === "string" && body.error.message
      ? body.error.message
      : response.statusText || "The server could not complete your request. Please try again.";
    throw new APIError(message, code, response.status);
  }

  return body.data;
}
