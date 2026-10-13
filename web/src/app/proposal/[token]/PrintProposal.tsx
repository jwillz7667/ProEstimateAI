"use client";

export function PrintProposal() {
  return (
    <button
      type="button"
      onClick={() => window.print()}
      className="proposal-print-control mb-8 inline-flex items-center justify-center rounded-full border border-ink-200 bg-white px-5 py-2.5 text-sm font-medium text-ink-700 hover:bg-ink-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500"
    >
      Print or save PDF
    </button>
  );
}
