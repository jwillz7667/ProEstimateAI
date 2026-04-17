"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  respondToSharedProposal,
  type ProposalDecision,
} from "@/lib/proposal";

interface Props {
  token: string;
  /** Primary brand color from the company (fallback to default brand orange). */
  primaryColor?: string | null;
}

type Mode = "idle" | "approving" | "declining" | "submitted" | "error";

export function ProposalActions({ token, primaryColor }: Props) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("idle");
  const [message, setMessage] = useState("");
  const [errorText, setErrorText] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const accent = primaryColor || "#FF9230";

  function open(decision: ProposalDecision) {
    setErrorText(null);
    setMessage("");
    setMode(decision === "approved" ? "approving" : "declining");
  }

  function cancel() {
    if (isPending) return;
    setMode("idle");
    setErrorText(null);
  }

  function submit(decision: ProposalDecision) {
    setErrorText(null);
    startTransition(async () => {
      try {
        await respondToSharedProposal(token, decision, message.trim());
        setMode("submitted");
        // Re-render the server component so the status + banner update.
        router.refresh();
      } catch (err) {
        const msg =
          err instanceof Error
            ? err.message
            : "Something went wrong. Please try again.";
        setErrorText(msg);
        setMode("error");
      }
    });
  }

  if (mode === "submitted") {
    // The page will re-render with the new status — this is just a transient
    // confirmation while router.refresh resolves.
    return (
      <div className="rounded-2xl border border-ink-100 bg-white p-6 text-center text-ink-700">
        Submitting your response…
      </div>
    );
  }

  const confirming =
    mode === "approving" || mode === "declining" || mode === "error";
  const pendingDecision: ProposalDecision | null =
    mode === "approving"
      ? "approved"
      : mode === "declining"
        ? "declined"
        : null;

  return (
    <div className="rounded-2xl border border-ink-100 bg-white p-6 shadow-sm">
      {!confirming && (
        <>
          <h2 className="text-xl font-semibold text-ink-950">
            Ready to move forward?
          </h2>
          <p className="mt-1 text-sm text-ink-600">
            Approve this proposal to let your contractor know you&apos;re ready
            to start, or decline if this isn&apos;t the right fit.
          </p>
          <div className="mt-6 flex flex-col sm:flex-row gap-3">
            <button
              type="button"
              onClick={() => open("approved")}
              className="inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 font-semibold text-white transition focus:outline-none focus-visible:ring-4 focus-visible:ring-offset-2"
              style={{
                backgroundColor: accent,
                boxShadow: `0 12px 28px -12px ${accent}99`,
              }}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2.5}
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-5 w-5"
                aria-hidden
              >
                <polyline points="20 6 9 17 4 12" />
              </svg>
              Approve Proposal
            </button>
            <button
              type="button"
              onClick={() => open("declined")}
              className="inline-flex items-center justify-center gap-2 rounded-full border border-ink-200 px-6 py-3 font-medium text-ink-700 transition hover:bg-ink-50"
            >
              Decline
            </button>
          </div>
        </>
      )}

      {confirming && pendingDecision && (
        <>
          <h2 className="text-xl font-semibold text-ink-950">
            {pendingDecision === "approved"
              ? "Approve this proposal?"
              : "Decline this proposal?"}
          </h2>
          <p className="mt-1 text-sm text-ink-600">
            {pendingDecision === "approved"
              ? "Your contractor will be notified and can start scheduling the work."
              : "Let your contractor know why — this is optional but helpful."}
          </p>

          <label className="mt-5 block text-sm font-medium text-ink-800">
            Message to your contractor{" "}
            <span className="text-ink-500 font-normal">(optional)</span>
          </label>
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            rows={3}
            maxLength={10000}
            disabled={isPending}
            placeholder={
              pendingDecision === "approved"
                ? "Looking forward to getting started!"
                : "Thanks for the proposal, but we're going in a different direction."
            }
            className="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 placeholder:text-ink-400 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/30"
          />

          {errorText && (
            <p
              role="alert"
              className="mt-4 rounded-lg border border-error/30 bg-error/10 px-3 py-2 text-sm text-error"
            >
              {errorText}
            </p>
          )}

          <div className="mt-6 flex flex-col sm:flex-row-reverse gap-3">
            <button
              type="button"
              onClick={() => submit(pendingDecision)}
              disabled={isPending}
              className="inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-60"
              style={
                pendingDecision === "approved"
                  ? {
                      backgroundColor: accent,
                      boxShadow: `0 12px 28px -12px ${accent}99`,
                    }
                  : {
                      backgroundColor: "#EF4444",
                      boxShadow: "0 12px 28px -12px rgba(239, 68, 68, 0.6)",
                    }
              }
            >
              {isPending ? (
                <Spinner />
              ) : pendingDecision === "approved" ? (
                "Confirm Approval"
              ) : (
                "Confirm Decline"
              )}
            </button>
            <button
              type="button"
              onClick={cancel}
              disabled={isPending}
              className="inline-flex items-center justify-center gap-2 rounded-full border border-ink-200 px-6 py-3 font-medium text-ink-700 transition hover:bg-ink-50 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Keep Reviewing
            </button>
          </div>
        </>
      )}
    </div>
  );
}

function Spinner() {
  return (
    <svg
      className="h-5 w-5 animate-spin"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
    >
      <circle
        className="opacity-25"
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        strokeWidth="4"
      />
      <path
        className="opacity-90"
        d="M4 12a8 8 0 0 1 8-8"
        stroke="currentColor"
        strokeWidth="4"
        strokeLinecap="round"
      />
    </svg>
  );
}
