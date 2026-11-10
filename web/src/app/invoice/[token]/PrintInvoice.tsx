"use client";

export function PrintInvoice() {
  return <button type="button" onClick={() => window.print()}
    className="rounded-full border border-ink-200 bg-white px-5 py-3 text-sm font-medium text-ink-700 hover:bg-ink-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500 print:hidden">
    Print invoice and receipts
  </button>;
}
