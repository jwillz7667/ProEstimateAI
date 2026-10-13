import { NextRequest } from "next/server";

/// Edge runtime keeps cold starts low + streams cleanly back to the browser.
export const runtime = "edge";

const DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions";
const DEEPSEEK_MODEL = "deepseek-chat";

/// How much of the user's prior chat to forward. The client also caps this,
/// and the server applies the same ceiling to bound upstream cost.
const MAX_FORWARDED_MESSAGES = 10;
const MAX_USER_MESSAGE_CHARS = 2000;
const MAX_TOTAL_PROMPT_CHARS = 12_000;

/// Per-IP rate limit: 20 messages / hour. In-memory Map is good enough for
/// a low-volume support widget on Vercel's Edge — each region starts fresh
/// so the cap is per-region, not global. Swap in Upstash later if volume
/// warrants.
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const RATE_LIMIT_MAX = 20;
const hits = new Map<string, { count: number; resetAt: number }>();

const SYSTEM_PROMPT = `You are the customer support assistant for ProEstimate AI, an iOS app for home-remodel contractors and homeowners.

Core product (what the app actually does — do not promise features that aren't in this list):
- The user takes one photo of a room and picks a project type (kitchen, bathroom, flooring, roofing, painting, siding, room remodel, exterior, custom) plus a quality tier (standard, premium, luxury).
- The app calls a backend AI pipeline that produces a photoreal remodel preview plus a suggested materials list with estimated quantities and costs.
- The user can turn the preview + materials into an Estimate: categorized line items (materials / labor / other), totals, tax, optional contingency, assumptions, exclusions, notes.
- Pro users can convert estimates into Proposals (shareable link for client approval) and Invoices (branded PDFs).
- Company branding (name, address, phone, email, website, colors, logo) is configured in Settings → Branding and appears on every exported PDF.
- Estimates can be exported as PDFs that include the company letterhead, before/after project photos, grouped line items, and totals.

Pricing / plans:
- Free tier: 5 lifetime AI preview generations and manual estimating tools. Starter preview credits never reset. AI estimate generation, quote exports, invoices, branding, and approval links require Pro.
- Pro: 2 new projects, 20 AI preview generations, 20 AI-generated estimates, and 50 quote exports per month. Daily and weekly limits also apply. Includes branded PDFs (no watermark), invoice creation, and client approval links. Monthly or annual; eligible new monthly subscribers can start a 7-day free trial. Refer users to the App Store for final prices and eligibility. Premium subscriptions are no longer offered.
- Subscriptions are billed through the Apple App Store. Cancellation is via iOS Settings → Apple ID → Subscriptions.

Account management:
- Delete account: Settings → Account → Delete Account in the app. Data is purged within 30 days.
- Sign in with Apple is supported.
- Password reset works through the email reset link.

Support / contact:
- support@proestimateai.com for product questions.
- privacy@proestimateai.com for privacy / data deletion.

STYLE:
- Friendly, direct, and concise. No marketing fluff.
- If the user asks about billing disputes, refund eligibility, or App Store policies, point them at Apple's refund flow (reportaproblem.apple.com) and offer to escalate to support@proestimateai.com.
- If the user asks something clearly unrelated to ProEstimate AI (generic coding help, weather, politics, other apps), say you can only help with ProEstimate AI questions and offer the support email.
- Never invent features, prices, or timelines. If you are not sure, say so and suggest emailing support@proestimateai.com.
- No markdown headings or code fences. Short paragraphs, plain prose. Lists are fine when genuinely useful.`;

interface IncomingMessage {
  role: unknown;
  content: unknown;
}

interface ValidMessage {
  role: "user" | "assistant";
  content: string;
}

function sanitize(messages: IncomingMessage[]): ValidMessage[] {
  const clean: ValidMessage[] = [];
  for (const m of messages) {
    if (m && typeof m === "object") {
      const role = m.role;
      const content = m.content;
      if (
        (role === "user" || role === "assistant") &&
        typeof content === "string" &&
        content.trim().length > 0
      ) {
        clean.push({
          role,
          content: content.slice(0, MAX_USER_MESSAGE_CHARS),
        });
      }
    }
  }
  return clean;
}

function pickClientIp(req: NextRequest): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]!.trim();
  const vercelIp = req.headers.get("x-real-ip");
  if (vercelIp) return vercelIp;
  return "unknown";
}

function hitRateLimit(ip: string): { allowed: boolean; retryInSec?: number } {
  const now = Date.now();
  const entry = hits.get(ip);
  if (!entry || entry.resetAt < now) {
    hits.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return { allowed: true };
  }
  if (entry.count >= RATE_LIMIT_MAX) {
    return {
      allowed: false,
      retryInSec: Math.max(1, Math.ceil((entry.resetAt - now) / 1000)),
    };
  }
  entry.count += 1;
  return { allowed: true };
}

export async function POST(req: NextRequest) {
  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    return new Response(
      "The support assistant is temporarily unavailable. Please email support@proestimateai.com.",
      { status: 503 },
    );
  }

  const ip = pickClientIp(req);
  const rl = hitRateLimit(ip);
  if (!rl.allowed) {
    return new Response(
      `You've hit the per-hour limit on the support assistant. Try again in ${rl.retryInSec} seconds, or email support@proestimateai.com.`,
      { status: 429, headers: { "Retry-After": String(rl.retryInSec) } },
    );
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON body.", { status: 400 });
  }

  if (!payload || typeof payload !== "object" || !("messages" in payload) ||
      !Array.isArray(payload.messages)) {
    return new Response("Please send a messages array.", { status: 400 });
  }
  const clean = sanitize(payload.messages.slice(-MAX_FORWARDED_MESSAGES));

  if (clean.length === 0) {
    return new Response("Please send at least one message.", { status: 400 });
  }

  const totalChars = clean.reduce((sum, m) => sum + m.content.length, 0);
  if (totalChars > MAX_TOTAL_PROMPT_CHARS) {
    return new Response(
      "The conversation is too long. Start a fresh chat and try a shorter question.",
      { status: 413 },
    );
  }

  const unavailable = "The assistant is temporarily unavailable. Please try again or email support@proestimateai.com.";
  let upstream: Response;
  try {
    upstream = await fetch(DEEPSEEK_ENDPOINT, {
      method: "POST",
      signal: AbortSignal.timeout(30_000),
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        messages: [{ role: "system", content: SYSTEM_PROMPT }, ...clean],
        temperature: 0.4,
        max_tokens: 700,
        stream: true,
      }),
    });
  } catch {
    return new Response(unavailable, { status: 502 });
  }

  if (!upstream.ok || !upstream.body) {
    await upstream.body?.cancel().catch(() => undefined);
    return new Response(
      unavailable,
      { status: upstream.status === 429 ? 429 : 502 },
    );
  }

  const reader = upstream.body.getReader();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let sseBuffer = "";

  function enqueueLine(line: string, controller: ReadableStreamDefaultController<Uint8Array>) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) return;
    const data = trimmed.slice(5).trim();
    if (!data || data === "[DONE]") return;
    try {
      const json: unknown = JSON.parse(data);
      if (!json || typeof json !== "object" || !("choices" in json) || !Array.isArray(json.choices)) return;
      const chunk: unknown = json.choices[0]?.delta?.content;
      if (typeof chunk === "string" && chunk) controller.enqueue(encoder.encode(chunk));
    } catch {
      // Keep-alive comments or malformed provider frames carry no text.
    }
  }

  // Transform DeepSeek's SSE stream into a plain text stream so the client
  // just concatenates bytes — no SSE parsing in the browser.
  const stream = new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        sseBuffer += decoder.decode();
        // Some providers close after a final data frame without a newline.
        if (sseBuffer) enqueueLine(sseBuffer, controller);
        controller.close();
        return;
      }
      sseBuffer += decoder.decode(value, { stream: true });
      const lines = sseBuffer.split("\n");
      sseBuffer = lines.pop() ?? "";
      for (const line of lines) {
        enqueueLine(line, controller);
      }
    },
    cancel() {
      reader.cancel().catch(() => undefined);
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store, no-transform",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
