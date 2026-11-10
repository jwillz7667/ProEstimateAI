import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Payment setup | ProEstimate AI", robots: { index: false, follow: false }, referrer: "no-referrer" };

export default function PaymentSetupPage() {
  return <main className="flex min-h-screen items-center justify-center bg-surface-secondary px-5 py-12 text-ink-900">
    <section className="w-full max-w-lg space-y-5 rounded-3xl border border-ink-200 bg-white p-7 sm:p-10">
      <p className="text-sm font-semibold uppercase tracking-widest text-ink-500">ProEstimate AI</p>
      <h1 className="text-3xl font-bold tracking-tight">Continue payment setup in the app</h1>
      <p className="leading-relaxed text-ink-600">Return to ProEstimate AI and open Settings → Customer payments. Tap Refresh payment status to check your business verification.</p>
      <p className="leading-relaxed text-ink-600">If your secure setup link expired, tap Continue secure setup in the app for a fresh link. Returning to this page does not activate payments or confirm a charge.</p>
      <Link href="/" className="inline-flex min-h-12 items-center rounded-xl bg-brand-500 px-5 py-3 font-semibold text-ink-900">Visit ProEstimate AI</Link>
    </section>
  </main>;
}
