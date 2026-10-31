import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { ResetPasswordForm } from "./ResetPasswordForm";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Reset your password",
  description: "Securely reset your ProEstimate AI password.",
  referrer: "no-referrer",
  robots: { index: false, follow: false, nocache: true, googleBot: { index: false, follow: false } },
  alternates: { canonical: "https://proestimateai.com/reset-password" },
};

export default function ResetPasswordPage() {
  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#101012] px-5 py-8 text-[#f7f7f8] sm:py-14">
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,rgba(255,146,48,0.10),transparent_65%)]" />
      <section aria-label="Account recovery" className="relative w-full max-w-[440px] rounded-[28px] border border-white/10 bg-[#1c1c1e] p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)] sm:p-8">
        <header className="mb-7 border-b border-white/10 pb-6">
          <Link href="/" className="inline-flex min-h-11 items-center gap-3 text-lg font-bold tracking-tight">
            <Image src="/icon-192.png" alt="" width={40} height={40} className="rounded-[12px]" priority />
            <span>ProEstimate <span className="text-brand-500">AI</span></span>
          </Link>
        </header>
        <ResetPasswordForm />
        <footer className="mt-7 flex items-center justify-between gap-4 border-t border-white/10 pt-5 text-xs text-ink-300">
          <Link href="/privacy" className="inline-flex min-h-11 items-center underline-offset-4 hover:text-white hover:underline">Privacy policy</Link>
          <Link href="/support" className="inline-flex min-h-11 items-center underline-offset-4 hover:text-white hover:underline">Need help?</Link>
        </footer>
      </section>
    </main>
  );
}
