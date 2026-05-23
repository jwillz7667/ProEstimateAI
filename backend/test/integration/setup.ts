import { execSync } from "node:child_process";
import { afterAll, beforeAll } from "vitest";

/**
 * Integration tests need a real Postgres. They use the same Prisma
 * client as production code, exercising real transactions, real
 * constraints, and real index behavior — see CLAUDE.md ("integration
 * tests use real DB ... mocks reserved for third-party APIs").
 *
 * The runner expects `TEST_DATABASE_URL` to point at a disposable
 * Postgres database (e.g. a local Docker or a dedicated CI database).
 * If the env var is missing the suite does not run — we'd rather skip
 * loudly than silently green-light commerce code without exercising it.
 *
 * On boot we:
 *   1. Override `DATABASE_URL` so every Prisma client created during
 *      tests connects to the test DB.
 *   2. Run `prisma migrate deploy` to bring the test DB up to the
 *      current schema. Idempotent; safe to run on a database that's
 *      already migrated.
 *   3. Set sentinel env values for JWT secrets so the env zod parser
 *      doesn't reject the process at module load.
 */
const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;

if (!TEST_DATABASE_URL) {
  // Vitest swallows console.warn at default verbosity — use stderr.
  process.stderr.write(
    "\n[integration] TEST_DATABASE_URL is not set. Set it to a disposable Postgres URL to run these tests.\n\n",
  );
  // Throw so the suite fails fast rather than appearing to pass.
  throw new Error(
    "TEST_DATABASE_URL is required for integration tests",
  );
}

process.env.DATABASE_URL = TEST_DATABASE_URL;
process.env.NODE_ENV = "test";

// Give the env zod parser something it accepts — these are 32+ chars
// and only used for JWT signing, which the commerce tests don't touch.
process.env.JWT_SECRET ??= "test-secret-test-secret-test-secret-aaaaa";
process.env.JWT_REFRESH_SECRET ??= "test-refresh-test-refresh-test-refresh-aaa";

// Make sure the App Store Server API truth-check stays off by default
// — tests stub out individual paths when they want to exercise it.
delete process.env.APP_STORE_API_KEY_ID;
delete process.env.APP_STORE_API_PRIVATE_KEY;
delete process.env.APP_STORE_ISSUER_ID;

beforeAll(() => {
  execSync("npx prisma migrate deploy", {
    cwd: process.cwd(),
    env: { ...process.env, DATABASE_URL: TEST_DATABASE_URL },
    stdio: "inherit",
  });
});

afterAll(async () => {
  // Lazy import so the disconnect call doesn't pull in the Prisma
  // client at module load (which would fix the connection string
  // before the env override above runs).
  const { prisma } = await import("../../src/config/database");
  await prisma.$disconnect();
});
