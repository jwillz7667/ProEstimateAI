import { prisma } from '../config/database';
import { logger } from '../config/logger';

/**
 * Pre-deploy online index creation.
 *
 * A plain `CREATE INDEX` takes a lock that blocks writes to the table for the
 * whole build. On a live table that is a write outage. Postgres offers
 * `CREATE INDEX CONCURRENTLY` to build without that lock — but it *cannot* run
 * inside a transaction, and Prisma wraps every migration in one. So these
 * indexes are deliberately kept OUT of the migration files (their migration
 * SQL is a documented no-op) and created here, in a standalone process that
 * runs BEFORE `prisma migrate deploy` in the container CMD.
 *
 * Every statement is idempotent (`IF NOT EXISTS`) so re-running on each deploy
 * is a no-op once the index exists. We additionally repair the one failure
 * mode `IF NOT EXISTS` cannot: an interrupted concurrent build leaves an
 * INVALID index behind, which `IF NOT EXISTS` would skip forever — giving the
 * planner an index it can never use. We detect and rebuild those.
 */

interface ConcurrentIndex {
  /** Index name as it appears in pg_class (matches Prisma's generated name). */
  readonly name: string;
  /** Table the index is built on, for log context. */
  readonly table: string;
  /** Column/expression list, e.g. '"originalTransactionId"'. */
  readonly columns: string;
}

// Keep this list in lockstep with the no-op'd migrations that "own" each index
// in Prisma's history. Adding an index here means its migration.sql is empty.
const CONCURRENT_INDEXES: readonly ConcurrentIndex[] = [
  {
    name: 'UserEntitlement_originalTransactionId_idx',
    table: 'UserEntitlement',
    columns: '"originalTransactionId"',
  },
];

/** Quote a Postgres identifier, guarding against accidental injection. */
function quoteIdent(identifier: string): string {
  if (!/^[A-Za-z0-9_]+$/.test(identifier)) {
    throw new Error(`Refusing to build SQL with unsafe identifier: ${identifier}`);
  }
  return `"${identifier}"`;
}

/**
 * Returns the validity of an existing index by name:
 *  - 'missing'  → no index with this name
 *  - 'valid'    → exists and usable
 *  - 'invalid'  → exists but a prior CONCURRENTLY build failed; unusable
 */
async function indexState(name: string): Promise<'missing' | 'valid' | 'invalid'> {
  const rows = await prisma.$queryRawUnsafe<{ indisvalid: boolean }[]>(
    `SELECT i.indisvalid
       FROM pg_class c
       JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = $1`,
    name,
  );
  if (rows.length === 0) return 'missing';
  return rows[0].indisvalid ? 'valid' : 'invalid';
}

async function ensureIndex(index: ConcurrentIndex): Promise<void> {
  const name = quoteIdent(index.name);
  const table = quoteIdent(index.table);

  const state = await indexState(index.name);

  if (state === 'valid') {
    logger.info({ index: index.name }, 'Index already present and valid — skipping');
    return;
  }

  if (state === 'invalid') {
    // A previous concurrent build was interrupted. IF NOT EXISTS would skip
    // this broken index forever, so drop it (also concurrently) first.
    logger.warn({ index: index.name }, 'Found INVALID index from interrupted build — rebuilding');
    await prisma.$executeRawUnsafe(`DROP INDEX CONCURRENTLY IF EXISTS ${name}`);
  }

  logger.info({ index: index.name, table: index.table }, 'Creating index CONCURRENTLY');
  // CONCURRENTLY requires running outside a transaction. $executeRawUnsafe
  // issues a single statement with no implicit BEGIN/COMMIT, so this is valid.
  await prisma.$executeRawUnsafe(
    `CREATE INDEX CONCURRENTLY IF NOT EXISTS ${name} ON ${table} (${index.columns})`,
  );
  logger.info({ index: index.name }, 'Index created');
}

async function main(): Promise<void> {
  if (CONCURRENT_INDEXES.length === 0) {
    logger.info('No concurrent indexes registered — nothing to do');
    return;
  }

  logger.info({ count: CONCURRENT_INDEXES.length }, 'Ensuring online indexes before migrate deploy');

  // Sequential, not parallel: each CONCURRENTLY build is I/O heavy and a single
  // failure should not leave siblings half-built with an ambiguous exit state.
  for (const index of CONCURRENT_INDEXES) {
    await ensureIndex(index);
  }

  logger.info('All online indexes ensured');
}

main()
  .then(async () => {
    await prisma.$disconnect();
    process.exit(0);
  })
  .catch(async (err) => {
    logger.error({ err }, 'Pre-deploy index creation failed');
    await prisma.$disconnect();
    // Non-zero exit aborts the container CMD chain before migrate deploy /
    // server start, so a broken deploy fails loudly instead of silently
    // running without the index.
    process.exit(1);
  });
