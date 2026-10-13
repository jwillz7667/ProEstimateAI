"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";

export default function ProposalError({ reset }: { error: Error; reset: () => void }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  function retry() {
    // Refresh rejected server data as well as resetting the client boundary.
    startTransition(() => {
      router.refresh();
      reset();
    });
  }

  return (
    <main className="min-h-screen bg-surface-secondary flex items-center justify-center px-6">
      <div className="max-w-md text-center">
        <h1 className="text-3xl font-bold text-ink-950 mb-3">Unable to load this proposal</h1>
        <p role="alert" className="text-ink-600 leading-relaxed mb-8">
          There was a problem connecting. Try again, or contact the contractor who shared this link.
        </p>
        <button
          type="button"
          onClick={retry}
          disabled={isPending}
          className="inline-flex items-center justify-center rounded-full bg-brand-500 px-6 py-3 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500"
        >
          {isPending ? "Trying again…" : "Try again"}
        </button>
      </div>
    </main>
  );
}
