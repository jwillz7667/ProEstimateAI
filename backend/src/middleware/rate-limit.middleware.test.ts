import { describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ stores: [] as { prefix: string }[], limits: [] as { store: unknown }[] }));
vi.mock("express-rate-limit", () => ({ default: (options: { store: unknown }) => { mocks.limits.push(options); return options; } }));
vi.mock("rate-limit-redis", () => ({ RedisStore: class {
  constructor(options: { prefix: string }) { mocks.stores.push(options); }
} }));
vi.mock("../config/redis", () => ({ getRedis: () => ({ call: vi.fn() }) }));
vi.mock("../config/env", () => ({ env: { NODE_ENV: "production" } }));
import "./rate-limit.middleware";
describe("rate limit store isolation", () => {
  it("keeps global, auth and share counts in distinct Redis keyspaces", () => {
    expect(mocks.stores.map((store) => store.prefix)).toEqual([
      "rate-limit:global:", "rate-limit:auth:", "rate-limit:share:",
    ]);
    expect(mocks.limits).toHaveLength(3);
    expect(mocks.limits.every((limit) => limit.store)).toBe(true);
  });
});
