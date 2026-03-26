import { Response } from 'express';

interface PaginationMeta {
  next_cursor: string | null;
}

interface ResponseMeta {
  request_id?: string;
  timestamp: string;
  pagination?: PaginationMeta;
}

export function sendSuccess<T>(
  res: Response,
  data: T,
  meta?: { pagination?: PaginationMeta; statusCode?: number }
) {
  const responseMeta: ResponseMeta = {
    request_id: (res.req as any).requestId,
    timestamp: new Date().toISOString(),
  };
  if (meta?.pagination) {
    responseMeta.pagination = meta.pagination;
  }
  res.status(meta?.statusCode ?? 200).json({
    ok: true,
    data,
    meta: responseMeta,
  });
}

export function sendError(
  res: Response,
  statusCode: number,
  error: {
    code: string;
    message: string;
    field_errors?: Record<string, string[]>;
    retryable?: boolean;
    paywall?: any;
  }
) {
  res.status(statusCode).json({
    ok: false,
    error,
    meta: {
      request_id: (res.req as any).requestId,
      timestamp: new Date().toISOString(),
      pagination: null,
    },
  });
}
