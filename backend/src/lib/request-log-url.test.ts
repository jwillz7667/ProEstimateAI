import { describe, expect, it } from "vitest";
import { requestLogUrl } from "./request-log-url";

describe("request log URL privacy", () => {
  it.each([
    ["/v1/proposals/share/secret/approve", "/v1/proposals/share/[redacted]/approve"],
    ["/v1/invoice-share/secret/checkout", "/v1/invoice-share/[redacted]/checkout"],
    ["/v1/follow-up-preferences/secret/unsubscribe", "/v1/follow-up-preferences/[redacted]/unsubscribe"],
    ["/v1/assets/secret/image?w=960", "/v1/assets/[redacted]/image?[redacted]"],
    ["/v1/generations/secret/preview", "/v1/generations/[redacted]/preview"],
    ["/v1/estimate-exports/secret/file", "/v1/estimate-exports/[redacted]/file"],
    ["/proposalS/share/secret", "/proposalS/share/[redacted]"],
    ["/v1/%69nvoice-share/secret", "/v1/%69nvoice-share/[redacted]"],
    ["https://user:password@example.test/v1/invoice-share/secret?key=private", "/v1/invoice-share/[redacted]?[redacted]"],
  ])("redacts bearer access in %s", (input, expected) => {
    expect(requestLogUrl(input)).toBe(expected);
  });
  it("discards both query keys and values without obscuring a normal route", () => {
    expect(requestLogUrl("/v1/auth/reset-password?token=secret&customer@example.test=x")).toBe("/v1/auth/reset-password?[redacted]");
    expect(requestLogUrl("/v1/projects/project-id")).toBe("/v1/projects/project-id");
  });
  it("fails closed on malformed paths and untrusted input", () => {
    expect(requestLogUrl("/v1/invoice-share/%zz-secret")).toBe("[invalid-url]");
    expect(requestLogUrl(undefined)).toBe("[invalid-url]");
  });
});
