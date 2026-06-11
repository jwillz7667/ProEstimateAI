import type { NextFunction, Request, Response } from 'express';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { requireAdmin } from './admin.middleware';
import { AuthenticationError, AuthorizationError } from '../lib/errors';

const isAdminUser = vi.hoisted(() => vi.fn<(userId: string) => Promise<boolean>>());
vi.mock('../lib/admin', () => ({ isAdminUser }));

function makeReq(userId?: string): Request {
  return { userId } as unknown as Request;
}

const res = {} as Response;

describe('requireAdmin', () => {
  beforeEach(() => {
    isAdminUser.mockReset();
  });

  it('calls next with no error for an admin user', async () => {
    isAdminUser.mockResolvedValue(true);
    const next = vi.fn() as unknown as NextFunction;

    await requireAdmin(makeReq('admin-1'), res, next);

    expect(isAdminUser).toHaveBeenCalledWith('admin-1');
    expect(next).toHaveBeenCalledTimes(1);
    expect((next as unknown as ReturnType<typeof vi.fn>).mock.calls[0][0]).toBeUndefined();
  });

  it('rejects a non-admin user with AuthorizationError (403)', async () => {
    isAdminUser.mockResolvedValue(false);
    const next = vi.fn() as unknown as NextFunction;

    await requireAdmin(makeReq('user-1'), res, next);

    const err = (next as unknown as ReturnType<typeof vi.fn>).mock.calls[0][0];
    expect(err).toBeInstanceOf(AuthorizationError);
    expect(err.statusCode).toBe(403);
    expect(isAdminUser).toHaveBeenCalledWith('user-1');
  });

  it('rejects an unauthenticated request with AuthenticationError (401)', async () => {
    const next = vi.fn() as unknown as NextFunction;

    await requireAdmin(makeReq(undefined), res, next);

    const err = (next as unknown as ReturnType<typeof vi.fn>).mock.calls[0][0];
    expect(err).toBeInstanceOf(AuthenticationError);
    expect(err.statusCode).toBe(401);
    // Never consults the allowlist when there's no user at all.
    expect(isAdminUser).not.toHaveBeenCalled();
  });

  it('forwards an unexpected lookup error to next', async () => {
    const boom = new Error('db down');
    isAdminUser.mockRejectedValue(boom);
    const next = vi.fn() as unknown as NextFunction;

    await requireAdmin(makeReq('user-2'), res, next);

    expect((next as unknown as ReturnType<typeof vi.fn>).mock.calls[0][0]).toBe(boom);
  });
});
