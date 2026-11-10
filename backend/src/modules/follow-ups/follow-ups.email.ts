import { env } from "../../config/env";
import type { FollowUpTarget } from "./follow-ups.target";

export interface FollowUpEmailPayload {
  from: string; to: string[]; reply_to?: string; subject: string; html: string; text: string;
  headers: Record<string, string>;
}

export class FollowUpDeliveryError extends Error {
  constructor(message: string, readonly retryable: boolean) { super(message); }
}

export function isFollowUpDeliveryConfigured() { return Boolean(env.RESEND_API_KEY); }

function escape(value: string) {
  return value.replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]!);
}

export function buildFollowUpEmail(target: FollowUpTarget, unsubscribeToken: string): FollowUpEmailPayload {
  const unsubscribePage = `${env.PUBLIC_WEB_BASE_URL.replace(/\/$/, "")}/reminders/${encodeURIComponent(unsubscribeToken)}`;
  const unsubscribeAPI = `${env.API_BASE_URL.replace(/\/$/, "").replace(/\/v1$/, "")}/v1/follow-up-preferences/${encodeURIComponent(unsubscribeToken)}/unsubscribe`;
  const subject = target.kind === "proposal" ? `Your proposal from ${target.companyName}` : `Invoice reminder from ${target.companyName}`;
  const description = target.kind === "proposal"
    ? "Your proposal is available to review. You can approve it, request changes or decline using the link below."
    : "An invoice is awaiting payment. Open it to see the current balance, payment history and instructions.";
  return {
    from: env.RESEND_FROM_EMAIL, to: [target.email!], ...(target.replyTo ? { reply_to: target.replyTo } : {}), subject,
    text: `${target.companyName}\n${target.title}\n\n${description}\n\nReview: ${target.url}\n\nStop reminders for this document: ${unsubscribePage}`,
    html: `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${escape(subject)}</title></head><body style="margin:0;background:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,Arial,sans-serif;color:#1f2937"><main style="max-width:560px;margin:24px auto;padding:32px;background:white;border-radius:16px"><h1 style="font-size:24px">${escape(target.companyName)}</h1><h2 style="font-size:18px">${escape(target.title)}</h2><p style="line-height:1.6">${escape(description)}</p><a href="${escape(target.url)}" style="display:inline-block;padding:14px 24px;background:#ff9230;color:#111827;border-radius:24px;font-weight:700;text-decoration:none">Review ${target.kind === "proposal" ? "proposal" : "invoice"}</a><p style="margin-top:28px;font-size:13px;line-height:1.5">${target.replyTo ? `Questions? Reply to ${escape(target.replyTo)}.` : `Contact ${escape(target.companyName)} with questions.`}</p><p style="font-size:12px"><a href="${escape(unsubscribePage)}" style="color:#4b5563">Stop reminders for this document</a></p></main></body></html>`,
    headers: { "List-Unsubscribe": `<${unsubscribeAPI}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
  };
}

/** Stable keys are reused for every retry; requests time out within the queue lease. */
export async function sendFollowUpEmail(payload: FollowUpEmailPayload, idempotencyKey: string): Promise<string> {
  if (!env.RESEND_API_KEY) throw new FollowUpDeliveryError("Email delivery is not configured.", false);
  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST", headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json", "Idempotency-Key": idempotencyKey },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(10_000),
    });
  } catch { throw new FollowUpDeliveryError("The email provider response could not be confirmed.", true); }
  if (!response.ok) throw new FollowUpDeliveryError(`The email provider returned HTTP ${response.status}.`, response.status === 429 || response.status >= 500);
  const data = await response.json() as { id?: unknown };
  if (typeof data.id !== "string" || !data.id) throw new FollowUpDeliveryError("The email provider response could not be confirmed.", true);
  return data.id;
}
