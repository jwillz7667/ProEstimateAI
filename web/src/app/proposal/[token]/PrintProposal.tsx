"use client";

import { useEffect } from "react";

export function PrintProposal() {
  useEffect(() => {
    let closedBeforePrint: HTMLDetailsElement[] | null = null;
    const expandForPrint = () => {
      if (closedBeforePrint !== null) return;
      closedBeforePrint = [...document.querySelectorAll<HTMLDetailsElement>("details[data-print-expand]:not([open])")];
      closedBeforePrint.forEach((details) => { details.open = true; });
    };
    const restoreReview = () => {
      closedBeforePrint?.forEach((details) => { details.open = false; });
      closedBeforePrint = null;
    };
    window.addEventListener("beforeprint", expandForPrint);
    window.addEventListener("afterprint", restoreReview);
    return () => {
      window.removeEventListener("beforeprint", expandForPrint);
      window.removeEventListener("afterprint", restoreReview);
      restoreReview();
    };
  }, []);
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
