import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { APIError, fetchAPI } from "@/lib/api";
import { ReminderPreference } from "./ReminderPreference";

export const metadata: Metadata = { title: "Reminder preferences | ProEstimate AI", robots: { index: false, follow: false }, referrer: "no-referrer" };

export default async function ReminderPreferencesPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  let suppressed = false;
  try {
    const result = await fetchAPI<{ suppressed: boolean }>(`/follow-up-preferences/${encodeURIComponent(token)}`);
    suppressed = result.suppressed;
  } catch (error) {
    if (error instanceof APIError && error.status === 404) notFound();
    throw error;
  }
  return (
    <main className="flex min-h-screen items-center justify-center bg-surface-secondary px-6 py-16">
      <section className="w-full max-w-lg rounded-3xl border border-ink-100 bg-white p-8 shadow-sm">
        <p className="text-sm font-semibold text-ink-500">ProEstimate AI</p>
        <h1 className="mt-3 text-3xl font-semibold text-ink-950">Reminder preferences</h1>
        <p className="mt-3 leading-relaxed text-ink-600">Stop follow-up emails for this document. The proposal or invoice stays available, and this does not change its approval or payment status.</p>
        <ReminderPreference token={token} initiallySuppressed={suppressed} />
      </section>
    </main>
  );
}
