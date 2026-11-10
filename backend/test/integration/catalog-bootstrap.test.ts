import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';

describe('production commerce catalog bootstrap', () => {
  it('creates the sellable and legacy restore catalog without customer records and preserves changes on repeat', async () => {
    const testUrl = process.env.TEST_DATABASE_URL;
    if (!testUrl) throw new Error('TEST_DATABASE_URL is required');
    const schema = `catalog_${randomUUID().replaceAll('-', '')}`;
    const databaseUrl = new URL(testUrl);
    databaseUrl.searchParams.set('schema', schema);
    const database = new PrismaClient({
      datasources: { db: { url: databaseUrl.toString() } },
    });
    const environment = { ...process.env, DATABASE_URL: databaseUrl.toString() };
    const runBootstrap = () => execFileSync('node', ['dist/scripts/bootstrap-catalog.js'], {
      env: environment,
      stdio: 'pipe',
      timeout: 60_000,
    });

    try {
      execFileSync('npx', ['prisma', 'migrate', 'deploy'], {
        env: environment,
        stdio: 'pipe',
        timeout: 60_000,
      });
      runBootstrap();

      const plans = await database.plan.findMany({ orderBy: { code: 'asc' } });
      expect(plans.map((plan) => plan.code)).toEqual([
        'FREE_STARTER', 'PRO_MONTHLY', 'PRO_ANNUAL', 'PREMIUM_MONTHLY', 'PREMIUM_ANNUAL',
      ]);
      expect(plans.filter((plan) => plan.code.startsWith('PREMIUM')).every((plan) => !plan.isActive)).toBe(true);
      const products = await database.subscriptionProduct.findMany({
        orderBy: { sortOrder: 'asc' },
        include: { plan: true },
      });
      expect(products.map((product) => ({
        productId: product.storeProductId,
        planCode: product.plan.code,
        price: product.priceDisplay,
        trial: product.hasIntroOffer,
      }))).toEqual([
        { productId: 'proestimate.pro.monthly', planCode: 'PRO_MONTHLY', price: '$19.99/mo', trial: true },
        { productId: 'proestimate.pro.annual', planCode: 'PRO_ANNUAL', price: '$199.99/yr', trial: true },
        { productId: 'proestimate.premium.monthly', planCode: 'PREMIUM_MONTHLY', price: '$49.99/mo', trial: false },
        { productId: 'proestimate.premium.annual', planCode: 'PREMIUM_ANNUAL', price: '$499.99/yr', trial: false },
      ]);
      expect(products[0].plan.featuresJson).toMatchObject({
        CAN_CREATE_INVOICE: true,
        LIMITS: { AI_GENERATION: { monthly: 20 } },
      });

      // Inspect every application table rather than only checking demo emails:
      // production startup must never import any customer or commerce history.
      const tables = await database.$queryRaw<{ table_name: string }[]>`
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = ${schema} AND table_type = 'BASE TABLE'
      `;
      for (const { table_name: table } of tables) {
        if (['_prisma_migrations', 'Plan', 'SubscriptionProduct'].includes(table)) continue;
        // Names originate in PostgreSQL's catalog; quote embedded quotes too.
        const identifier = `"${table.replaceAll('"', '""')}"`;
        const rows = await database.$queryRawUnsafe<{ count: bigint }[]>(
          `SELECT count(*) AS count FROM ${identifier}`,
        );
        expect(rows[0].count, `${table} must remain empty`).toBe(0n);
      }

      await database.plan.update({
        where: { code: 'PRO_MONTHLY' },
        data: {
          displayName: 'Restored monthly plan',
          isActive: false,
          featuresJson: { preserved: true, LIMITS: { PROJECT_CREATED: { monthly: 17 } } },
        },
      });
      await database.subscriptionProduct.update({
        where: { storeProductId: 'proestimate.pro.monthly' },
        data: { priceDisplay: '$27.00/mo', hasIntroOffer: false, sortOrder: 9 },
      });
      const expectedPlans = await database.plan.findMany({ orderBy: { code: 'asc' } });
      const expectedProducts = await database.subscriptionProduct.findMany({ orderBy: { storeProductId: 'asc' } });

      runBootstrap();
      expect(await database.plan.findMany({ orderBy: { code: 'asc' } })).toEqual(expectedPlans);
      expect(await database.subscriptionProduct.findMany({ orderBy: { storeProductId: 'asc' } })).toEqual(expectedProducts);
    } finally {
      // Schema is generated locally from a UUID; shared test fixtures stay intact.
      await database.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await database.$disconnect();
    }
  }, 120_000);
});
