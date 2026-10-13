import type { Request, Response, NextFunction } from 'express';
import { describe, expect, it, vi } from 'vitest';
const sendError = vi.hoisted(() => vi.fn());
vi.mock('../lib/envelope', () => ({ sendError }));
vi.mock('../config/logger', () => ({ logger: { error: vi.fn(), warn: vi.fn(), debug: vi.fn() } }));
import { errorHandler } from './error-handler.middleware';
describe('invalid HTTP request bodies', () => {
  it.each([['entity.parse.failed', 400], ['entity.too.large', 413], ['charset.unsupported', 415], ['encoding.unsupported', 415]])('returns a non-retryable client error for %s', (type, status) => {
    sendError.mockClear();
    const error = Object.assign(new Error('Private parser detail'), { type });
    errorHandler(error, { path: '/v1/test' } as Request, { headersSent: false, writableEnded: false } as Response, vi.fn() as NextFunction);
    expect(sendError).toHaveBeenCalledWith(expect.anything(), status, expect.objectContaining({ retryable: false }));
    expect(sendError.mock.calls[0][2].message).not.toContain('Private');
  });
});
