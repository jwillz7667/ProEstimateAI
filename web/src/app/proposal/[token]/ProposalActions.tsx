"use client";

import { useId, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { respondToSharedProposal, type ProposalDecision } from "@/lib/proposal";

interface Props {
  token: string;
  primaryColor?: string | null;
  documentHash?: string | null;
  consentText?: string;
  consentVersion?: string;
}

type Mode = "idle" | ProposalDecision | "submitted";

function foregroundForHex(hex: string): string {
  const channels = [1, 3, 5].map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  const luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  return luminance > 0.179 ? "#000000" : "#FFFFFF";
}

export function ProposalActions({ token, primaryColor, documentHash, consentText, consentVersion }: Props) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("idle");
  const [message, setMessage] = useState("");
  const [signerName, setSignerName] = useState("");
  const [consent, setConsent] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const submitting = useRef(false);
  const formId = useId();
  const accent = primaryColor && /^#[a-f\d]{6}$/i.test(primaryColor) ? primaryColor : "#FF9230";
  const foreground = foregroundForHex(accent);
  const pendingDecision = mode !== "idle" && mode !== "submitted" ? mode : null;
  const approving = pendingDecision === "approved";
  const changing = pendingDecision === "changes_requested";
  const versionAvailable = Boolean(documentHash && consentText && consentVersion);
  const formComplete = approving
    ? versionAvailable && signerName.trim().length > 0 && consent
    : !changing || message.trim().length > 0;

  function open(decision: ProposalDecision) {
    setErrorText(null);
    setMessage("");
    setSignerName("");
    setConsent(false);
    setMode(decision);
  }

  function cancel() {
    if (submitting.current || isPending) return;
    setMode("idle");
    setErrorText(null);
  }

  function submit(decision: ProposalDecision) {
    if (submitting.current || !formComplete) return;
    submitting.current = true;
    setErrorText(null);
    startTransition(async () => {
      try {
        await respondToSharedProposal(token, decision, message.trim(),
          decision === "approved" && documentHash && consentVersion ? {
            signer_name: signerName.trim(), acceptance_consent: true,
            consent_version: consentVersion, document_hash: documentHash,
          } : undefined,
          documentHash ?? undefined,
        );
        setMode("submitted");
        router.refresh();
      } catch (error) {
        setErrorText(error instanceof Error ? error.message : "Your response couldn't be confirmed. Refresh this proposal before trying again.");
      } finally {
        submitting.current = false;
      }
    });
  }

  if (mode === "submitted") {
    return <div role="status" className="rounded-2xl border border-ink-100 bg-white p-6 text-center text-ink-700">Your response has been recorded. Thank you.</div>;
  }

  return (
    <div className="rounded-2xl border border-ink-100 bg-white p-6 shadow-sm">
      {!pendingDecision ? (
        <>
          <h2 className="text-xl font-semibold text-ink-950">Ready to move forward?</h2>
          <p className="mt-1 text-sm text-ink-600">Review the scope, price and terms. You can approve this version, ask for changes or decline.</p>
          <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
            <button type="button" onClick={() => open("approved")} className="min-h-12 rounded-full px-6 py-3 font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4" style={{ backgroundColor: accent, color: foreground }}>Approve Proposal</button>
            <button type="button" onClick={() => open("changes_requested")} className="min-h-12 rounded-full border border-ink-200 px-6 py-3 font-medium text-ink-800 hover:bg-ink-50">Request Changes</button>
            <button type="button" onClick={() => open("declined")} className="min-h-12 rounded-full px-6 py-3 font-medium text-ink-600 hover:bg-ink-50">Decline</button>
          </div>
        </>
      ) : (
        <form onSubmit={(event) => { event.preventDefault(); submit(pendingDecision); }}>
          <h2 className="text-xl font-semibold text-ink-950">{approving ? "Approve this proposal" : changing ? "What would you like to change?" : "Decline this proposal?"}</h2>
          <p className="mt-1 text-sm text-ink-600">{approving ? "Your acknowledgement will be saved with this exact proposal version." : changing ? "Your contractor can prepare a new version. This version will stay available for reference." : "Let your contractor know why. Your message is optional."}</p>

          {approving && (
            <>
              {!versionAvailable && <p role="alert" className="mt-4 text-sm text-error">This proposal version could not be verified. Refresh the page before approving.</p>}
              <label htmlFor={`${formId}-name`} className="mt-5 block text-sm font-medium text-ink-800">Your full name</label>
              <input id={`${formId}-name`} name="signer_name" autoComplete="name" value={signerName} onChange={(event) => setSignerName(event.target.value)} maxLength={200} required disabled={isPending} className="mt-1 min-h-12 w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:outline focus:outline-2 focus:outline-offset-2" />
              <label htmlFor={`${formId}-consent`} className="mt-4 flex cursor-pointer items-start gap-3 rounded-xl bg-ink-50 p-4 text-sm leading-relaxed text-ink-800">
                <input id={`${formId}-consent`} name="acceptance_consent" type="checkbox" checked={consent} onChange={(event) => setConsent(event.target.checked)} required disabled={isPending || !versionAvailable} className="mt-1 h-5 w-5 shrink-0" />
                <span>{consentText ?? "Review the proposal version before approving."}</span>
              </label>
              <p className="mt-2 text-xs text-ink-500">The name you enter is self-attested. This link does not independently verify your identity.</p>
            </>
          )}

          <label htmlFor={`${formId}-message`} className="mt-5 block text-sm font-medium text-ink-800">{changing ? "Requested changes" : "Message to your contractor"}{!changing && <span className="font-normal text-ink-500"> (optional)</span>}</label>
          <textarea id={`${formId}-message`} value={message} onChange={(event) => setMessage(event.target.value)} rows={3} maxLength={10000} required={changing} disabled={isPending} className="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:outline focus:outline-2 focus:outline-offset-2" placeholder={changing ? "Describe the scope, materials or pricing you would like revised." : "Add a note for your contractor."} />
          {errorText && <p role="alert" className="mt-4 rounded-lg border border-error/30 bg-error/10 px-3 py-2 text-sm text-error">{errorText}</p>}
          <div className="mt-6 flex flex-col gap-3 sm:flex-row-reverse">
            <button type="submit" disabled={isPending || !formComplete} className="min-h-12 rounded-full px-6 py-3 font-semibold disabled:cursor-not-allowed disabled:opacity-50" style={{ backgroundColor: approving ? accent : changing ? "#1F2937" : "#B91C1C", color: approving ? foreground : "#FFFFFF" }}>{isPending ? "Sending response…" : approving ? "Confirm Approval" : changing ? "Send Change Request" : "Confirm Decline"}</button>
            <button type="button" onClick={cancel} disabled={isPending} className="min-h-12 rounded-full border border-ink-200 px-6 py-3 font-medium text-ink-700 hover:bg-ink-50 disabled:opacity-60">Keep Reviewing</button>
          </div>
        </form>
      )}
    </div>
  );
}
