import type { Metadata } from "next";
import Link from "next/link";
import { SupportChat } from "./SupportChat";

export const metadata: Metadata = {
  title: "Support",
  description:
    "Get help with ProEstimate AI — FAQs, live AI assistant, and a direct email to the team.",
  alternates: { canonical: "https://proestimateai.com/support" },
};

const faqs: Array<{ q: string; a: string }> = [
  {
    q: "How do AI remodel previews work?",
    a: "Take one photo of the space, pick your project type (kitchen, bathroom, flooring, etc.) and a quality tier, then tap Generate. Our AI produces a photoreal preview of the finished room plus a suggested materials list.",
  },
  {
    q: "What's included in the free plan?",
    a: "Three AI remodel previews and three quote exports. Exports on the free plan include a small ProEstimate AI watermark. Pro removes the watermark and unlocks unlimited previews, invoices, branded PDFs, and client approval links.",
  },
  {
    q: "How much is Pro and how do I subscribe?",
    a: "Pro is available monthly or annually through the App Store. Annual saves about 37% versus monthly. There is a 7-day free trial on the monthly plan. Manage or cancel anytime from iOS Settings → Apple ID → Subscriptions.",
  },
  {
    q: "Can I use my own company branding on estimates?",
    a: "Yes. Open Settings → Branding in the app and upload your logo, address, phone, email, website, and brand colors. Every exported PDF — estimate, proposal, and invoice — uses that branding on Pro.",
  },
  {
    q: "Do my project photos get used to train AI?",
    a: "No. Photos are processed in real time by our AI provider and are not used to train models. See our Privacy Policy for the full breakdown.",
  },
  {
    q: "How do I cancel or delete my account?",
    a: "In the app: Settings → Account → Delete Account. This permanently removes your projects, estimates, and subscription association within 30 days.",
  },
  {
    q: "Do you support contractors working in teams?",
    a: "The current release is single-user per company. Team seats are on the roadmap — email us and we'll add you to the early access list.",
  },
  {
    q: "What devices and iOS versions are supported?",
    a: "iPhone and iPad running iOS 26.4 or later. The app is optimized for iPhone 14 and newer.",
  },
];

export default function SupportPage() {
  return (
    <main className="min-h-screen bg-surface">
      <header className="border-b border-gray-100">
        <div className="mx-auto max-w-4xl px-6 py-6 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            ProEstimate<span className="text-brand-500">AI</span>
          </Link>
          <Link
            href="/"
            className="text-sm text-brand-500 hover:text-brand-600 font-medium"
          >
            &larr; Back to Home
          </Link>
        </div>
      </header>

      <section className="mx-auto max-w-4xl px-6 pt-14 pb-8">
        <h1 className="text-4xl sm:text-5xl font-bold text-gray-900 mb-3">
          How can we help?
        </h1>
        <p className="text-lg text-gray-600 max-w-2xl">
          Search the common questions below, or ask our AI assistant anything
          about ProEstimate AI. If you still need a human, email{" "}
          <a
            href="mailto:support@proestimateai.com"
            className="text-brand-500 hover:text-brand-600 font-medium"
          >
            support@proestimateai.com
          </a>{" "}
          and we usually reply within one business day.
        </p>
      </section>

      <section className="mx-auto max-w-4xl px-6 pb-8">
        <SupportChat />
      </section>

      <section className="mx-auto max-w-4xl px-6 pb-16">
        <h2 className="text-2xl font-semibold text-gray-900 mb-6">
          Frequently asked
        </h2>
        <div className="divide-y divide-gray-100 rounded-2xl border border-gray-100 bg-white shadow-sm">
          {faqs.map((item) => (
            <details
              key={item.q}
              className="group px-6 py-5 [&_summary::-webkit-details-marker]:hidden"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4">
                <span className="text-base font-medium text-gray-900">
                  {item.q}
                </span>
                <span
                  aria-hidden
                  className="text-brand-500 transition-transform group-open:rotate-45 text-xl leading-none"
                >
                  +
                </span>
              </summary>
              <p className="mt-3 text-gray-600 leading-relaxed">{item.a}</p>
            </details>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-4xl px-6 pb-20">
        <div className="rounded-2xl border border-gray-100 bg-white p-8 shadow-sm">
          <h2 className="text-2xl font-semibold text-gray-900 mb-2">
            Still need help?
          </h2>
          <p className="text-gray-600 mb-6">
            Send us a note and we will reply from a real person.
          </p>
          <div className="flex flex-col sm:flex-row gap-4">
            <a
              href="mailto:support@proestimateai.com"
              className="inline-flex items-center justify-center rounded-lg bg-brand-500 px-5 py-3 text-sm font-semibold text-white hover:bg-brand-600 transition"
            >
              Email support
            </a>
            <a
              href="mailto:privacy@proestimateai.com"
              className="inline-flex items-center justify-center rounded-lg border border-gray-200 px-5 py-3 text-sm font-semibold text-gray-900 hover:border-brand-500 hover:text-brand-500 transition"
            >
              Privacy questions
            </a>
          </div>
        </div>
      </section>

      <footer className="border-t border-gray-100 py-8 text-sm text-gray-500">
        <div className="mx-auto max-w-4xl px-6 flex items-center justify-between">
          <p>&copy; 2026 ProEstimate AI. All rights reserved.</p>
          <div className="flex gap-6">
            <Link
              href="/privacy"
              className="text-brand-500 hover:text-brand-600 font-medium"
            >
              Privacy
            </Link>
            <Link
              href="/terms"
              className="text-brand-500 hover:text-brand-600 font-medium"
            >
              Terms
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}
