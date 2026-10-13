import { beforeEach, describe, expect, it, vi } from "vitest";
const send = vi.hoisted(() => vi.fn());
vi.mock("../config/env", () => ({
  env: {
    RESEND_API_KEY: "test-key",
    RESEND_FROM_EMAIL: "Test <test@example.test>",
  },
}));
vi.mock("../config/logger", () => ({
  logger: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));
vi.mock("resend", () => ({
  Resend: class {
    emails = { send };
  },
}));
import { sendInvoiceEmail } from "./email";
beforeEach(() => {
  send.mockReset();
  send.mockResolvedValue({ error: null });
});
describe("invoice email delivery", () => {
  it("attaches the rendered invoice and omits the broken empty view link", async () => {
    const pdf = { filename: "INV-123.pdf", content: Buffer.from("%PDF-1.7\n") };
    await sendInvoiceEmail(
      "client@example.test",
      "",
      "Test Contractor",
      "$120.00",
      pdf,
    );
    expect(send.mock.calls[0][0].attachments).toEqual([
      { ...pdf, contentType: "application/pdf" },
    ]);
    expect(send.mock.calls[0][0].html).toContain("invoice PDF is attached");
    expect(send.mock.calls[0][0].html).not.toContain('href=""');
  });
  it("offers clear contact instructions when no link or attachment is available", async () => {
    await sendInvoiceEmail(
      "client@example.test",
      "",
      "Test Contractor",
      "$120.00",
    );
    expect(send.mock.calls[0][0].html).toContain("Contact your contractor");
    expect(send.mock.calls[0][0].html).not.toContain("View Invoice");
  });
});
