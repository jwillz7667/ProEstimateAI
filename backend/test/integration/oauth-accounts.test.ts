import { beforeEach, describe, expect, it, vi } from 'vitest';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { resetCommerceTables } from './helpers';

const claims = vi.hoisted(() => ({ apple: vi.fn(), google: vi.fn() }));
vi.mock('../../src/lib/apple-auth', () => ({ verifyAppleIdentityToken: claims.apple }));
vi.mock('../../src/lib/google-auth', async (original) => ({ ...await original<object>(), verifyGoogleIdentityToken: claims.google }));
import { appleSignIn, googleSignIn } from '../../src/modules/auth/auth.service';

const providers = [
  { name: 'Apple', mock: claims.apple, identity: 'appleUserId' as const,
    verified: { sub: 'apple-account-subject', email: 'apple-owner@example.test', email_verified: true },
    signIn: () => appleSignIn({ identity_token: 'local-mocked-provider-proof', authorization_code: 'local-code', email: 'untrusted-client@example.test' }) },
  { name: 'Google', mock: claims.google, identity: 'googleId' as const,
    verified: { sub: 'google-account-subject', email: 'google-owner@gmail.com', emailVerified: true },
    signIn: () => googleSignIn({ identity_token: 'local-mocked-provider-proof', email: 'untrusted-client@example.test' }) },
];
beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
  vi.clearAllMocks();
});

for (const provider of providers) describe(`${provider.name} account persistence with verified-provider boundary mocked`, () => {
  it('creates a fresh account with starter entitlement and signs the same subject back in without repeated email', async () => {
    provider.mock.mockResolvedValue(provider.verified);
    const first = await provider.signIn();
    expect(first.user.email).toBe(provider.verified.email);
    expect(first.user[provider.identity]).toBe(provider.verified.sub);
    expect(first.user.passwordHash).toBeNull();
    const entitlement = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: first.user.id }, include: { plan: true } });
    expect(entitlement.status).toBe('FREE');
    expect(entitlement.plan.code).toBe('FREE_STARTER');
    expect(await prisma.usageBucket.findFirst({ where: { userId: first.user.id } })).toMatchObject({
      includedQuantity: 0, consumedQuantity: 0, source: 'STARTER_CREDITS',
    });
    provider.mock.mockResolvedValue({ sub: provider.verified.sub });
    const returning = await provider.signIn();
    expect(returning.user.id).toBe(first.user.id);
    expect(returning.refreshToken).not.toBe(first.refreshToken);
    expect(await prisma.company.count()).toBe(1);
    expect(await prisma.user.count()).toBe(1);
    expect(await prisma.usageBucket.count()).toBe(1);
    await prisma.user.update({ where: { id: first.user.id }, data: { isActive: false } });
    await expect(provider.signIn()).rejects.toMatchObject({ statusCode: 401 });
  });

  it('handles concurrent first sign-ins without duplicate companies or lost starter credits', async () => {
    provider.mock.mockResolvedValue(provider.verified);
    const attempts = await Promise.allSettled(Array.from({ length: 6 }, () => provider.signIn()));
    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(6);
    expect(await prisma.company.count()).toBe(1);
    expect(await prisma.user.count()).toBe(1);
    expect(await prisma.userEntitlement.count()).toBe(1);
    expect(await prisma.usageBucket.count()).toBe(1);
    expect(await prisma.refreshToken.count()).toBe(6);
  });
});
