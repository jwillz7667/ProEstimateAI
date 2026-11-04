import { randomUUID } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { StripeMerchant } from '@prisma/client';
import { prisma } from '../../src/config/database';
import { merchantStatus, startMerchantOnboarding } from '../../src/modules/invoice-checkout/invoice-checkout.service';
import { MerchantCountryRejectedError } from '../../src/modules/invoice-checkout/merchant-country';
import { MerchantPaymentGateway } from '../../src/modules/invoice-checkout/stripe-gateway';

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}

class MerchantGateway implements MerchantPaymentGateway {
  liveMode = false;
  calls: StripeMerchant[] = [];
  accounts = new Map<string, string>();
  writes = 0;
  handler?: (merchant: StripeMerchant, verifyLease?: () => Promise<void>) => Promise<string>;
  linkFails = false;
  async createMerchant(merchant: StripeMerchant, verifyLease?: () => Promise<void>) {
    this.calls.push(merchant);
    if (this.handler) return this.handler(merchant, verifyLease);
    await verifyLease?.();
    return this.create(merchant);
  }
  create(merchant: StripeMerchant) {
    if (!this.accounts.has(merchant.requestId)) {
      this.accounts.set(merchant.requestId, `acct_${randomUUID()}`);
      this.writes += 1;
    }
    return this.accounts.get(merchant.requestId)!;
  }
  async merchantReady(_accountId: string) { return false; }
  async onboardingLink(_accountId: string, _returnUrl: string, _refreshUrl: string) {
    if (this.linkFails) throw new Error('Link unavailable');
    return 'https://connect.stripe.com/setup/fixture';
  }
}

async function fixture() {
  const company = await prisma.company.create({ data: { name: 'Onboarding fixture' } });
  const user = await prisma.user.create({ data: { companyId: company.id, role: 'OWNER', fullName: 'Owner', email: `${randomUUID()}@example.test` } });
  const gateway = new MerchantGateway();
  const start = (country = 'US') => startMerchantOnboarding(company.id, user.id, country, gateway);
  const row = () => prisma.stripeMerchant.findUniqueOrThrow({ where: { companyId: company.id } });
  return { company, user, gateway, start, row };
}

describe('merchant onboarding country recovery with durable provider claims', () => {
  beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

  it('rejects unavailable countries before reserving and allows a corrected European selection', async () => {
    const t = await fixture();
    await expect(t.start('AQ')).rejects.toMatchObject({ statusCode: 400 });
    expect(await prisma.stripeMerchant.count()).toBe(0);
    expect(t.gateway.calls).toHaveLength(0);
    await t.start('de');
    expect((await t.row()).country).toBe('DE');
    const status = await merchantStatus(t.company.id, t.user.id, t.gateway);
    expect(status.supported_countries).toHaveLength(44);
    expect(status.country).toBe('DE');
  });

  it('commits release of a first definitive rejection so the correct country can start a new request', async () => {
    const t = await fixture();
    t.gateway.handler = async () => { throw new MerchantCountryRejectedError(); };
    await expect(t.start('CA')).rejects.toBeInstanceOf(MerchantCountryRejectedError);
    const rejectedId = t.gateway.calls[0].requestId;
    expect(await prisma.stripeMerchant.count()).toBe(0);
    expect((await merchantStatus(t.company.id, t.user.id, t.gateway)).country).toBeNull();
    t.gateway.handler = undefined;
    await t.start('US');
    expect((await t.row()).requestId).not.toBe(rejectedId);
    expect(t.gateway.writes).toBe(1);
  });

  it('keeps original country, payload and UUID after a lost response and replays one provider account', async () => {
    const t = await fixture();
    t.gateway.handler = async merchant => { t.gateway.create(merchant); throw new Error('Lost provider response'); };
    await expect(t.start()).rejects.toThrow('Lost provider response');
    const pending = await t.row();
    expect(pending.creationStarted).toBe(true);
    expect(pending.creationLeaseId).toBeNull();
    await expect(t.start('CA')).rejects.toMatchObject({ statusCode: 409 });
    t.gateway.handler = undefined;
    await t.start();
    const connected = await t.row();
    expect(connected.requestId).toBe(pending.requestId);
    expect(connected.createdAt).toEqual(pending.createdAt);
    expect(t.gateway.calls.map(call => [call.requestId, call.country, call.displayName, call.contactEmail])).toEqual([
      [pending.requestId, 'US', pending.displayName, pending.contactEmail], [pending.requestId, 'US', pending.displayName, pending.contactEmail],
    ]);
    expect(t.gateway.writes).toBe(1);
  });

  it('never releases a later country rejection after an ambiguous earlier attempt', async () => {
    const t = await fixture();
    t.gateway.handler = async () => { throw new Error('Timeout'); };
    await expect(t.start()).rejects.toThrow('Timeout');
    const pending = await t.row();
    t.gateway.handler = async () => { throw new MerchantCountryRejectedError(); };
    await expect(t.start()).rejects.toThrow('earlier payment setup attempt still needs reconciliation');
    expect((await t.row()).requestId).toBe(pending.requestId);
    await expect(t.start('CA')).rejects.toMatchObject({ statusCode: 409 });
  });

  it('treats default-created legacy reservations as attempted, including countries outside the new list', async () => {
    const t = await fixture();
    const legacy = await prisma.stripeMerchant.create({ data: { companyId: t.company.id, country: 'AQ', displayName: 'Legacy merchant' } });
    expect(legacy.creationStarted).toBe(true);
    t.gateway.handler = async () => { throw new MerchantCountryRejectedError(); };
    await expect(t.start('AQ')).rejects.toMatchObject({ statusCode: 409 });
    expect((await t.row()).requestId).toBe(legacy.requestId);
    expect((await merchantStatus(t.company.id, t.user.id, t.gateway)).country).toBe('AQ');
  });

  it('blocks overlapping setup while a first rejection is pending, then releases only its exact claim', async () => {
    const t = await fixture(), entered = deferred<void>(), finish = deferred<void>();
    t.gateway.handler = async () => { entered.resolve(); await finish.promise; throw new MerchantCountryRejectedError(); };
    const first = t.start('CA');
    const firstResult = first.catch(error => error);
    await entered.promise;
    await expect(t.start('CA')).rejects.toThrow('already being prepared');
    expect(t.gateway.calls).toHaveLength(1);
    finish.resolve();
    expect(await firstResult).toBeInstanceOf(MerchantCountryRejectedError);
    expect(await prisma.stripeMerchant.count()).toBe(0);
    t.gateway.handler = undefined;
    await t.start('US');
    expect(t.gateway.writes).toBe(1);
  });

  it('blocks overlapping creates and reuses the established account after the first succeeds', async () => {
    const t = await fixture(), entered = deferred<void>(), finish = deferred<void>();
    t.gateway.handler = async merchant => { entered.resolve(); await finish.promise; return t.gateway.create(merchant); };
    const first = t.start();
    await entered.promise;
    await expect(t.start()).rejects.toThrow('already being prepared');
    finish.resolve();
    await first;
    await t.start();
    expect(t.gateway.calls).toHaveLength(1);
    expect((await t.row()).creationLeaseId).toBeNull();
    await expect(t.start('CA')).rejects.toMatchObject({ statusCode: 409 });
  });

  it('resumes a crashed expired claim with the original UUID and preserves its ambiguous history', async () => {
    const t = await fixture();
    const old = await prisma.stripeMerchant.create({ data: { companyId: t.company.id, country: 'US', displayName: 'Original', creationStarted: true,
      creationLeaseId: randomUUID(), creationLeaseExpiresAt: new Date(Date.now() + 90_000) } });
    await expect(t.start()).rejects.toThrow('already being prepared');
    expect(t.gateway.calls).toHaveLength(0);
    await prisma.stripeMerchant.update({ where: { companyId: t.company.id }, data: { creationLeaseExpiresAt: new Date(Date.now() - 1) } });
    t.gateway.handler = async () => { throw new MerchantCountryRejectedError(); };
    await expect(t.start()).rejects.toThrow('earlier payment setup attempt');
    expect((await t.row()).requestId).toBe(old.requestId);
    expect(t.gateway.calls[0].displayName).toBe('Original');
  });

  it('rejects an expired claim immediately before the actual provider write', async () => {
    const t = await fixture();
    t.gateway.handler = async (merchant, verifyLease) => {
      await prisma.stripeMerchant.update({ where: { companyId: t.company.id }, data: { creationLeaseExpiresAt: new Date(Date.now() - 1) } });
      await verifyLease?.();
      return t.gateway.create(merchant);
    };
    await expect(t.start()).rejects.toThrow('preparation expired');
    expect(t.gateway.writes).toBe(0);
    expect((await t.row()).creationStarted).toBe(true);
  });

  it('does not let a late first rejection delete or clear a newer active claim', async () => {
    const t = await fixture(), enteredFirst = deferred<void>(), enteredSecond = deferred<void>(), finishFirst = deferred<void>(), finishSecond = deferred<void>();
    t.gateway.handler = async merchant => {
      if (t.gateway.calls.length === 1) { enteredFirst.resolve(); await finishFirst.promise; throw new MerchantCountryRejectedError(); }
      enteredSecond.resolve(); await finishSecond.promise; return t.gateway.create(merchant);
    };
    const firstResult = t.start().catch(error => error);
    await enteredFirst.promise;
    const original = await t.row();
    await prisma.stripeMerchant.update({ where: { companyId: t.company.id }, data: { creationLeaseExpiresAt: new Date(Date.now() - 1) } });
    const second = t.start();
    await enteredSecond.promise;
    const newer = await t.row();
    expect(newer.creationLeaseId).not.toBe(original.creationLeaseId);
    finishFirst.resolve();
    expect(await firstResult).toMatchObject({ statusCode: 409 });
    expect((await t.row()).creationLeaseId).toBe(newer.creationLeaseId);
    finishSecond.resolve();
    await second;
    expect((await t.row()).requestId).toBe(original.requestId);
    expect(t.gateway.writes).toBe(1);
  });

  it('does not let a late successful response overwrite a superseding claim', async () => {
    const t = await fixture(), entered = deferred<void>(), finish = deferred<void>();
    t.gateway.handler = async merchant => {
      if (t.gateway.calls.length === 1) { entered.resolve(); await finish.promise; }
      return t.gateway.create(merchant);
    };
    const firstResult = t.start().catch(error => error);
    await entered.promise;
    await prisma.stripeMerchant.update({ where: { companyId: t.company.id }, data: { creationLeaseExpiresAt: new Date(Date.now() - 1) } });
    await t.start();
    const saved = await t.row();
    finish.resolve();
    expect(await firstResult).toMatchObject({ statusCode: 409 });
    expect((await t.row()).accountId).toBe(saved.accountId);
    expect(t.gateway.writes).toBe(1);
  });

  it('retains a successfully created account when only its hosted link fails', async () => {
    const t = await fixture();
    t.gateway.linkFails = true;
    await expect(t.start()).rejects.toThrow('Link unavailable');
    expect((await t.row()).accountId).not.toBeNull();
    t.gateway.linkFails = false;
    await t.start();
    expect(t.gateway.calls).toHaveLength(1);
  });
});
