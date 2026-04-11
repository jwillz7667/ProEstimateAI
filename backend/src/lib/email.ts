import { Resend } from 'resend';
import { env } from '../config/env';
import { logger } from '../config/logger';

const resend = env.RESEND_API_KEY ? new Resend(env.RESEND_API_KEY) : null;

interface SendEmailParams {
  to: string;
  subject: string;
  html: string;
}

export async function sendEmail({ to, subject, html }: SendEmailParams): Promise<void> {
  if (!resend) {
    logger.warn('RESEND_API_KEY not set — skipping email to %s (subject: %s)', to, subject);
    return;
  }

  const { error } = await resend.emails.send({
    from: env.RESEND_FROM_EMAIL,
    to,
    subject,
    html,
  });

  if (error) {
    logger.error({ err: error, to, subject }, 'Failed to send email');
    throw new Error(`Email send failed: ${error.message}`);
  }

  logger.info({ to, subject }, 'Email sent');
}

export async function sendPasswordResetEmail(email: string, resetUrl: string): Promise<void> {
  const html = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto; padding: 40px 20px; color: #1a1a1a;">
  <h2 style="margin: 0 0 16px;">Reset Your Password</h2>
  <p style="line-height: 1.6; color: #444;">
    We received a request to reset your ProEstimate AI password. Click the button below to choose a new one.
  </p>
  <a href="${resetUrl}" style="display: inline-block; margin: 24px 0; padding: 12px 28px; background: #F97316; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600;">
    Reset Password
  </a>
  <p style="line-height: 1.6; color: #444;">
    If you didn't request this, you can safely ignore this email. The link expires in 1 hour.
  </p>
  <hr style="border: none; border-top: 1px solid #e5e5e5; margin: 32px 0;" />
  <p style="font-size: 13px; color: #999;">ProEstimate AI</p>
</body>
</html>`.trim();

  await sendEmail({
    to: email,
    subject: 'Reset your ProEstimate AI password',
    html,
  });
}

export async function sendProposalEmail(
  clientEmail: string,
  proposalUrl: string,
  companyName: string,
  clientMessage?: string,
): Promise<void> {
  const messageBlock = clientMessage
    ? `<p style="line-height: 1.6; color: #444; background: #f9f9f9; padding: 16px; border-radius: 8px; margin: 16px 0;">${escapeHtml(clientMessage)}</p>`
    : '';

  const html = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto; padding: 40px 20px; color: #1a1a1a;">
  <h2 style="margin: 0 0 16px;">You Have a New Proposal</h2>
  <p style="line-height: 1.6; color: #444;">
    <strong>${escapeHtml(companyName)}</strong> has sent you a project proposal for your review.
  </p>
  ${messageBlock}
  <a href="${proposalUrl}" style="display: inline-block; margin: 24px 0; padding: 12px 28px; background: #F97316; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600;">
    View Proposal
  </a>
  <p style="line-height: 1.6; color: #444;">
    Click the button above to review the full proposal, including scope of work, materials, and pricing.
  </p>
  <hr style="border: none; border-top: 1px solid #e5e5e5; margin: 32px 0;" />
  <p style="font-size: 13px; color: #999;">Sent via ProEstimate AI on behalf of ${escapeHtml(companyName)}</p>
</body>
</html>`.trim();

  await sendEmail({
    to: clientEmail,
    subject: `Proposal from ${companyName}`,
    html,
  });
}

export async function sendInvoiceEmail(
  clientEmail: string,
  invoiceUrl: string,
  companyName: string,
  amount: string,
): Promise<void> {
  const html = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto; padding: 40px 20px; color: #1a1a1a;">
  <h2 style="margin: 0 0 16px;">Invoice from ${escapeHtml(companyName)}</h2>
  <p style="line-height: 1.6; color: #444;">
    You have received an invoice for <strong>${escapeHtml(amount)}</strong>.
  </p>
  <a href="${invoiceUrl}" style="display: inline-block; margin: 24px 0; padding: 12px 28px; background: #F97316; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600;">
    View Invoice
  </a>
  <p style="line-height: 1.6; color: #444;">
    Click the button above to view the full invoice details and payment information.
  </p>
  <hr style="border: none; border-top: 1px solid #e5e5e5; margin: 32px 0;" />
  <p style="font-size: 13px; color: #999;">Sent via ProEstimate AI on behalf of ${escapeHtml(companyName)}</p>
</body>
</html>`.trim();

  await sendEmail({
    to: clientEmail,
    subject: `Invoice for ${amount} from ${companyName}`,
    html,
  });
}

function escapeHtml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
