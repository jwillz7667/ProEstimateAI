"use client";

import { useRef, useState, useTransition } from "react";
import { fetchAPI } from "@/lib/api";

export function ReminderPreference({ token, initiallySuppressed }: { token: string; initiallySuppressed: boolean }) {
  const [suppressed, setSuppressed] = useState(initiallySuppressed);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const submitting = useRef(false);
  function stop() {
    if (submitting.current || suppressed) return;
    submitting.current = true;
    setError(null);
    startTransition(async () => {
      try {
        await fetchAPI(`/follow-up-preferences/${encodeURIComponent(token)}/unsubscribe`, { method: "POST" });
        setSuppressed(true);
      } catch (failure) { setError(failure instanceof Error ? failure.message : "Your preference couldn't be saved. Please try again."); }
      finally { submitting.current = false; }
    });
  }
  if (suppressed) return <p role="status" className="mt-6 rounded-xl bg-green-50 p-4 text-green-900">Reminders for this document have been stopped.</p>;
  return (
    <div className="mt-6">
      <button type="button" onClick={stop} disabled={pending} className="min-h-12 w-full rounded-full bg-brand-500 px-6 py-3 font-semibold text-black disabled:opacity-50">{pending ? "Saving…" : "Stop reminders for this document"}</button>
      {error && <p role="alert" className="mt-4 text-sm text-error">{error}</p>}
    </div>
  );
}
