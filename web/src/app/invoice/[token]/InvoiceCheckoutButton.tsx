"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { fetchAPI } from "@/lib/api";

export function InvoiceCheckoutButton({ token, processing, label, accent, testMode = false }: { token: string; processing: boolean; label: string; accent: string; testMode?: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(processing ? "Your payment is processing. Refresh to check its confirmed status." : null);
  async function pay() {
    if (busy) return;
    setBusy(true); setMessage(null);
    try {
      const result = await fetchAPI<{ url: string | null; state: string }>(`/invoice-share/${encodeURIComponent(token)}/checkout`, {
        method: "POST", body: JSON.stringify({ payment_scope: "next_installment" }),
      });
      if (result.url) {
        const url = new URL(result.url);
        if (url.protocol !== "https:" || url.hostname !== "checkout.stripe.com") throw new Error("The secure payment link could not be verified. Contact your contractor.");
        window.location.assign(url.href);
        return;
      }
      setMessage(result.state === "processing" ? "Your payment is processing or awaiting verified confirmation. Please wait and refresh its status."
        : "This checkout is no longer available. Refresh the invoice before trying again.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Payment setup could not be confirmed. Refresh before trying again.");
    } finally { setBusy(false); }
  }
  const luminance = accent.slice(1).match(/../g)!.map(hex => {
    const value = parseInt(hex, 16) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  }).reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
  const foreground = (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) ? "#111111" : "#FFFFFF";
  return <section className="space-y-3 rounded-2xl border border-ink-200 bg-white p-6 print:hidden" aria-labelledby="online-payment-title">
    <h2 id="online-payment-title" className="text-xl font-semibold">Secure online payment</h2>
    <p className="text-sm text-ink-600">Pay your contractor through Stripe. Your invoice updates after the payment is verified.</p>
    {testMode ? <p className="rounded-lg bg-amber-50 p-3 text-sm font-semibold text-ink-900">Test environment only. No real payment will be collected.</p> : null}
    {!processing ? <button onClick={pay} disabled={busy} style={{ backgroundColor: accent, color: foreground }}
      className="min-h-12 w-full rounded-xl px-5 py-3 text-base font-semibold disabled:opacity-60">
      {busy ? "Preparing secure checkout…" : label}
    </button> : null}
    {message ? <p role="status" className="text-sm text-ink-600">{message}</p> : null}
    <button onClick={() => router.refresh()} disabled={busy} className="min-h-11 rounded-lg px-1 text-sm font-semibold underline underline-offset-4">Refresh payment status</button>
  </section>;
}
