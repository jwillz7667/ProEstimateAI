import type { Request, Response } from 'express';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({ verify: vi.fn(), user: vi.fn() }));
vi.mock('../lib/jwt', () => ({ verifyAccessToken: mocks.verify }));
vi.mock('../config/database', () => ({ prisma: { user: { findUnique: mocks.user } } }));
import { requireAuth } from './auth.middleware';
beforeEach(() => {
  vi.resetAllMocks();
  mocks.verify.mockReturnValue({ userId: 'user', companyId: 'original-company' });
});
async function request() {
  const req = { headers: { authorization: 'Bearer signed' } } as Request;
  const next = vi.fn();
  await requireAuth(req, {} as Response, next);
  return { req, next };
}
describe('access token current membership', () => {
  it.each([null, { isActive: false, companyId: 'original-company' }, { isActive: true, companyId: 'new-company' }])('rejects deleted, disabled, or moved accounts: %j', async (user) => {
    mocks.user.mockResolvedValue(user);
    const { req, next } = await request();
    expect(next.mock.calls[0][0]).toMatchObject({ statusCode: 401 });
    expect(req.companyId).toBeUndefined();
  });
  it('allows current active membership', async () => {
    mocks.user.mockResolvedValue({ isActive: true, companyId: 'original-company' });
    const { req, next } = await request();
    expect(req.companyId).toBe('original-company');
    expect(next).toHaveBeenCalledWith();
  });
  it('propagates database outages without expiring a valid session', async () => {
    const outage = new Error('Database unavailable');
    mocks.user.mockRejectedValue(outage);
    expect((await request()).next).toHaveBeenCalledWith(outage);
  });
});
