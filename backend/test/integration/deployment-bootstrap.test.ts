import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';

/** Exercise the actual container bootstrap against an isolated, empty schema. */
describe('deployment bootstrap', () => {
  it('migrates before building indexes, then safely repeats on an existing database', async () => {
    const testUrl = process.env.TEST_DATABASE_URL;
    if (!testUrl) throw new Error('TEST_DATABASE_URL is required');
    const schema = `bootstrap_${randomUUID().replaceAll('-', '')}`;
    const url = new URL(testUrl);
    url.searchParams.set('schema', schema);
    const database = new PrismaClient({ datasources: { db: { url: url.toString() } } });
    const dockerfile = readFileSync('Dockerfile', 'utf8');
    const commandLine = dockerfile.split('\n').find((line) => line.startsWith('CMD ['));
    expect(commandLine).toBeDefined();
    const command: unknown = JSON.parse(commandLine!.slice(4));
    if (!Array.isArray(command) || command.length !== 3 || typeof command[2] !== 'string') {
      throw new Error('Expected Docker CMD ["sh", "-c", "..."]');
    }
    const serverCommand = ' && exec node dist/index.js';
    expect(command[2].endsWith(serverCommand)).toBe(true);
    const bootstrap = command[2].slice(0, -serverCommand.length);
    // A same-named index in the ordinary test schema must not make the
    // bootstrap incorrectly skip the index in the new isolated schema.
    execFileSync('node', ['dist/scripts/pre-deploy-indexes.js'], {
      env: { ...process.env, DATABASE_URL: testUrl },
      stdio: 'pipe',
      timeout: 60_000,
    });
    try {
      for (let attempt = 0; attempt < 2; attempt++) {
        execFileSync('sh', ['-c', bootstrap], {
          env: { ...process.env, DATABASE_URL: url.toString() },
          stdio: 'pipe',
          timeout: 60_000,
        });
        const indexes = await database.$queryRaw<{ indisvalid: boolean }[]>`
          SELECT i.indisvalid FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_index i ON i.indexrelid = c.oid
          WHERE n.nspname = ${schema}
          AND c.relname = 'UserEntitlement_originalTransactionId_idx'
        `;
        expect(indexes).toEqual([{ indisvalid: true }]);
      }
    } finally {
      // Identifier is generated locally from a UUID, never user input.
      await database.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await database.$disconnect();
    }
  }, 120_000);
});
