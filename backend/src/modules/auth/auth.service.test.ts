import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  user: { findUnique: vi.fn(), update: vi.fn() },
  refreshToken: { findUnique: vi.fn(), create: vi.fn(), deleteMany: vi.fn() },
  apple: vi.fn(), google: vi.fn(), access: vi.fn(), refresh: vi.fn(), verify: vi.fn(),
  sendReset: vi.fn(),
  env: { PUBLIC_WEB_BASE_URL: "https://proestimateai.com", API_BASE_URL: "https://api.example.test" },
}));
vi.mock("../../config/env", () => ({ env: mocks.env }));
vi.mock("../../config/database", () => ({ prisma: {
  user: mocks.user, refreshToken: mocks.refreshToken,
  $transaction: async (fn: (tx: unknown) => unknown) => fn({ user: mocks.user, refreshToken: mocks.refreshToken }),
} }));
vi.mock("../../lib/apple-auth", () => ({ verifyAppleIdentityToken: mocks.apple }));
vi.mock("../../lib/google-auth", () => ({
  verifyGoogleIdentityToken: mocks.google,
  GoogleAuthNotConfiguredError: class extends Error {},
}));
vi.mock("../../lib/jwt", () => ({
  signAccessToken: mocks.access, signRefreshToken: mocks.refresh, verifyRefreshToken: mocks.verify,
}));
vi.mock("../../lib/email", () => ({ sendPasswordResetEmail: mocks.sendReset }));
import { appleSignIn, forgotPassword, googleSignIn, refresh } from "./auth.service";

const user = { id: "user-1", companyId: "company-current", isActive: true, company: { id: "company-current" } };
const providers = [
  { name: "Apple", claim: mocks.apple, idField: "appleUserId", call: () => appleSignIn({ identity_token: "signed", authorization_code: "code", email: "victim@example.test" }), verified: { email_verified: true } },
  { name: "Google", claim: mocks.google, idField: "googleId", call: () => googleSignIn({ identity_token: "signed", email: "victim@example.test" }), verified: { emailVerified: true, hostedDomain: "example.test" } },
];
beforeEach(() => {
  vi.resetAllMocks();
  mocks.access.mockReturnValue("access");
  mocks.refresh.mockReturnValue("refresh");
  mocks.user.update.mockResolvedValue(user);
  mocks.env.PUBLIC_WEB_BASE_URL = "https://proestimateai.com";
});

describe("password reset website delivery", () => {
  it("emails a browser-only token matching the stored single-use reset token", async () => {
    mocks.user.findUnique.mockResolvedValue({ ...user, email: "owner@example.test", passwordHash: "existing-hash" });
    const started = Date.now();
    await forgotPassword({ email: "owner@example.test" });

    expect(mocks.sendReset).toHaveBeenCalledTimes(1);
    const [recipient, link] = mocks.sendReset.mock.calls[0];
    const url = new URL(link);
    const token = new URLSearchParams(url.hash.slice(1)).get("token");
    expect(recipient).toBe("owner@example.test");
    expect(url.origin).toBe("https://proestimateai.com");
    expect(url.pathname).toBe("/reset-password");
    expect(url.search).toBe("");
    expect(token).toMatch(/^[a-f0-9]{64}$/);
    const stored = mocks.user.update.mock.calls[0][0].data;
    expect(stored.passwordResetToken).toBe(token);
    expect(stored.passwordResetExpiresAt.getTime()).toBeGreaterThanOrEqual(started + 60 * 60 * 1000);
  });

  it("keeps the reset form on the configured website when its base has a path", async () => {
    mocks.env.PUBLIC_WEB_BASE_URL = "https://preview.example.test/site/?source=setup";
    mocks.user.findUnique.mockResolvedValue({ ...user, email: "owner@example.test", passwordHash: "existing-hash" });
    await forgotPassword({ email: "owner@example.test" });
    const url = new URL(mocks.sendReset.mock.calls[0][1]);
    expect(url.origin + url.pathname).toBe("https://preview.example.test/reset-password");
    expect(url.search).toBe("");
    expect(url.hostname).not.toBe("api.example.test");
  });

  it.each([null, { ...user, isActive: false }, { ...user, passwordHash: null }])(
    "keeps the generic response for unavailable or provider-only accounts: %j",
    async (record) => {
      mocks.user.findUnique.mockResolvedValue(record);
      await expect(forgotPassword({ email: "unknown@example.test" })).resolves.toBeUndefined();
      expect(mocks.user.update).not.toHaveBeenCalled();
      expect(mocks.sendReset).not.toHaveBeenCalled();
    },
  );
});
for (const provider of providers) {
  describe(`${provider.name} identity boundary`, () => {
    it("uses only verified signed email for linking, never client email", async () => {
      provider.claim.mockResolvedValue({ sub: "provider-owner", email: "OWNER@example.test", ...provider.verified });
      mocks.user.findUnique.mockResolvedValueOnce(null).mockResolvedValueOnce(user);
      await provider.call();
      expect(mocks.user.findUnique.mock.calls[1][0]).toEqual({ where: { email: "owner@example.test" }, include: { company: true } });
      expect(mocks.user.update).toHaveBeenCalledWith({ where: { id: user.id }, data: { [provider.idField]: "provider-owner" }, include: { company: true } });
    });
    it.each([{}, { email: "victim@example.test" }])("rejects unsigned/unverified email for a new identity: %j", async (claims) => {
      provider.claim.mockResolvedValue({ sub: "new-owner", ...claims });
      mocks.user.findUnique.mockResolvedValue(null);
      await expect(provider.call()).rejects.toThrow(/unverified/);
      expect(mocks.user.findUnique).toHaveBeenCalledTimes(1);
      expect(mocks.user.update).not.toHaveBeenCalled();
      expect(mocks.refreshToken.create).not.toHaveBeenCalled();
    });
    it("allows a previously linked subject without repeated email claims", async () => {
      provider.claim.mockResolvedValue({ sub: "provider-owner" });
      mocks.user.findUnique.mockResolvedValue(user);
      await expect(provider.call()).resolves.toMatchObject({ accessToken: "access" });
      expect(mocks.user.update).not.toHaveBeenCalled();
    });
    it.each([{ isActive: false }, { [provider.idField]: "different-owner" }])("rejects disabled accounts and conflicting identity links: %j", async (fields) => {
      provider.claim.mockResolvedValue({ sub: "provider-owner", email: "owner@example.test", ...provider.verified });
      mocks.user.findUnique.mockResolvedValueOnce(null).mockResolvedValueOnce({ ...user, ...fields });
      await expect(provider.call()).rejects.toThrow(/Unable to sign in/);
      expect(mocks.user.update).not.toHaveBeenCalled();
      expect(mocks.refreshToken.create).not.toHaveBeenCalled();
    });
    it("rejects a disabled previously linked subject", async () => {
      provider.claim.mockResolvedValue({ sub: "provider-owner" });
      mocks.user.findUnique.mockResolvedValue({ ...user, isActive: false });
      await expect(provider.call()).rejects.toThrow(/deactivated/);
      expect(mocks.refreshToken.create).not.toHaveBeenCalled();
    });
  });
}
describe("refresh rotation", () => {
  beforeEach(() => {
    mocks.verify.mockReturnValue({ userId: user.id, companyId: "old-company" });
    mocks.refreshToken.findUnique.mockResolvedValue({ id: "session", userId: user.id, expiresAt: new Date(Date.now() + 60_000) });
    mocks.user.findUnique.mockResolvedValue(user);
    mocks.refreshToken.deleteMany.mockResolvedValue({ count: 1 });
  });
  it("uses current company membership when rotating", async () => {
    await refresh("old-token");
    expect(mocks.access).toHaveBeenCalledWith({ userId: user.id, companyId: user.companyId });
    expect(mocks.refreshToken.create).toHaveBeenCalledTimes(1);
  });
  it("allows only the winner of concurrent rotation to mint tokens", async () => {
    mocks.refreshToken.deleteMany.mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 });
    const results = await Promise.allSettled([refresh("old-token"), refresh("old-token")]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((r) => r.status === "rejected")).toHaveLength(1);
    expect(mocks.refreshToken.create).toHaveBeenCalledTimes(1);
  });
  it.each([null, { ...user, isActive: false }])("rejects missing or disabled user", async (record) => {
    mocks.user.findUnique.mockResolvedValue(record);
    await expect(refresh("old-token")).rejects.toThrow(/unavailable/);
    expect(mocks.refreshToken.create).not.toHaveBeenCalled();
  });
  it("rejects a session with inconsistent ownership", async () => {
    mocks.refreshToken.findUnique.mockResolvedValue({ id: "session", userId: "another-user", expiresAt: new Date(Date.now() + 60_000) });
    await expect(refresh("old-token")).rejects.toThrow(/unavailable/);
    expect(mocks.refreshToken.create).not.toHaveBeenCalled();
  });
});

 describe("Google authoritative email linking", () => {
  it("rejects linking verified third-party email without Workspace authority", async () => {
    mocks.google.mockResolvedValue({ sub: "new-google", email: "owner@example.test", emailVerified: true });
    mocks.user.findUnique.mockResolvedValueOnce(null).mockResolvedValueOnce(user);
    await expect(googleSignIn({ identity_token: "signed" })).rejects.toThrow(/existing account/);
    expect(mocks.user.update).not.toHaveBeenCalled();
    expect(mocks.refreshToken.create).not.toHaveBeenCalled();
  });
  it("allows verified Gmail account linking without Workspace claims", async () => {
    mocks.google.mockResolvedValue({ sub: "gmail-owner", email: "owner@gmail.com", emailVerified: true });
    mocks.user.findUnique.mockResolvedValueOnce(null).mockResolvedValueOnce(user);
    await expect(googleSignIn({ identity_token: "signed" })).resolves.toMatchObject({ accessToken: "access" });
    expect(mocks.user.update).toHaveBeenCalled();
  });
});
