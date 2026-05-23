import { defineConfig } from "vitest/config";

// Default test runner targets unit tests sitting next to source files.
// Integration tests have their own config — vitest.integration.config.ts.
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    globals: false,
    testTimeout: 10_000,
  },
});
