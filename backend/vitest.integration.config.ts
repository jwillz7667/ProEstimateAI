import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/integration/**/*.test.ts"],
    globals: false,
    setupFiles: ["test/integration/setup.ts"],
    // Integration tests share a single Postgres schema and rely on
    // truncate-between-tests for isolation. Running them serially keeps
    // a renaming wipe in one test from yanking the rug out from under
    // another that's still mid-transaction.
    fileParallelism: false,
    pool: "forks",
    poolOptions: {
      forks: { singleFork: true },
    },
    testTimeout: 30_000,
    hookTimeout: 60_000,
  },
});
