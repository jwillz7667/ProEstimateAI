import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { APIError } from "@/lib/api";
import { getSharedInvoice, invoiceMoney, paymentMethodLabel, type SharedInvoice } from "@/lib/invoice";
import { PrintInvoice } from "./PrintInvoice";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Customer invoice", robots: { index: false, follow: false }, referrer: "no-referrer",
};

const displayDate = (value: string | null) => value
  ? new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(value)) : "Not specified";

export default async function InvoicePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  let data: SharedInvoice;
  try { data = await getSharedInvoice(token); }
  catch (error) {
    if (error instanceof APIError && error.status === 404) notFound();
    throw error;
  }
  const { invoice, company, client, project } = data;
  const money = (amount: number) => invoiceMoney(amount, invoice.currency_code);
  const isVoid = invoice.status === "void";
  const isPaid = !isVoid && invoice.amount_due === 0;
  const accent = company.primary_color && /^#[0-9a-fA-F]{6}$/.test(company.primary_color) ? company.primary_color : "#FF9230";
  const status = isVoid ? "Void" : isPaid ? "Paid" : invoice.amount_paid > 0 ? "Partially paid" : "Awaiting payment";
  const totals: Array<[string, number]> = [["Subtotal", invoice.subtotal], ["Tax", invoice.tax_amount]];
  if (invoice.discount_amount > 0) totals.push(["Discount", -invoice.discount_amount]);
  totals.push(["Invoice total", invoice.total_amount], ["Recorded payments", invoice.amount_paid]);

  return <main className="min-h-screen bg-surface-secondary text-ink-900 print:bg-white">
    <div className="h-1.5" style={{ backgroundColor: accent }} />
    <article className="mx-auto max-w-3xl space-y-8 px-5 py-10 sm:px-8 sm:py-14">
      <header className="flex flex-wrap items-start justify-between gap-5">
        <div><p className="text-sm font-semibold uppercase tracking-widest text-ink-500">{company.name}</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">Invoice {invoice.invoice_number}</h1>
          <p className="mt-2 text-lg text-ink-600">{project.title}</p></div>
        <span className="rounded-full bg-white px-4 py-2 font-semibold ring-1 ring-ink-200">{status}</span>
      </header>
      <section aria-label="Billing details" className="grid gap-5 rounded-2xl border border-ink-200 bg-white p-6 sm:grid-cols-3">
        <div><p className="text-sm text-ink-500">Prepared for</p><p className="mt-1 font-semibold">{client.name}</p></div>
        <div><p className="text-sm text-ink-500">Issued</p><p className="mt-1 font-semibold">{displayDate(invoice.issued_date)}</p></div>
        <div><p className="text-sm text-ink-500">Due</p><p className="mt-1 font-semibold">{displayDate(invoice.due_date)}</p></div>
      </section>
      <section aria-labelledby="work-title" className="rounded-2xl border border-ink-200 bg-white p-6">
        <h2 id="work-title" className="mb-4 text-xl font-semibold">Work and materials</h2>
        <ul className="divide-y divide-ink-100">{data.line_items.map((item, index) => <li key={`${index}-${item.name}`} className="flex items-start justify-between gap-5 py-4">
          <div className="min-w-0"><h3 className="break-words font-medium">{item.name}</h3>
            {item.description ? <p className="mt-1 whitespace-pre-wrap break-words text-sm text-ink-600">{item.description}</p> : null}
            <p className="mt-1 text-sm text-ink-500">{item.quantity} {item.unit} × {money(item.unit_cost)}</p></div>
          <p className="shrink-0 font-semibold tabular-nums">{money(item.line_total)}</p>
        </li>)}</ul>
        <dl className="ml-auto mt-5 w-full max-w-[24rem] space-y-3 border-t border-ink-200 pt-5">
          {totals.map(([label, amount]) =>
            <div key={String(label)} className="flex justify-between gap-4"><dt className="text-ink-600">{label}</dt><dd className="tabular-nums">{money(Number(amount))}</dd></div>)}
          <div className="flex justify-between gap-4 border-t border-ink-200 pt-4 text-xl font-bold"><dt>{isVoid ? "Invoice void" : "Remaining balance"}</dt><dd>{isVoid ? "—" : money(invoice.amount_due)}</dd></div>
        </dl>
      </section>
      {!isVoid && data.installments.length ? <section aria-labelledby="schedule-title" className="rounded-2xl border border-ink-200 bg-white p-6">
        <h2 id="schedule-title" className="text-xl font-semibold">Payment schedule</h2>
        <ul className="mt-3 divide-y divide-ink-100">{data.installments.map((item) => <li key={item.id} className="flex justify-between gap-5 py-4">
          <div><h3 className="font-medium">{item.title}</h3><p className="mt-1 text-sm text-ink-500">{item.due_date ? `Due ${displayDate(item.due_date)}` : "Due at the agreed milestone"}</p></div>
          <div className="text-right"><p className="font-semibold">{money(item.amount)}</p><p className="mt-1 text-sm text-ink-500">{item.amount_due === 0 ? "Paid" : `${money(item.amount_due)} remaining`}</p></div>
        </li>)}</ul>
      </section> : null}
      {!isVoid && !isPaid && invoice.payment_instructions ? <section className="rounded-2xl border border-ink-200 bg-white p-6">
        <h2 className="text-xl font-semibold">How to pay</h2><p className="mt-3 whitespace-pre-wrap break-words text-ink-600">{invoice.payment_instructions}</p>
      </section> : null}
      {data.payments.length ? <section aria-labelledby="receipts-title" className="rounded-2xl border border-ink-200 bg-white p-6">
        <h2 id="receipts-title" className="text-xl font-semibold">Payment receipts</h2>
        <p className="mt-2 text-sm text-ink-500">Payments recorded by {company.name}. Contact your contractor if a payment is missing.</p>
        <ul className="mt-3 divide-y divide-ink-100">{data.payments.map((payment) => <li key={payment.id} className="flex justify-between gap-4 py-4">
          <div><p className="font-medium">{paymentMethodLabel(payment.method)}</p><p className="mt-1 text-sm text-ink-500">{payment.recorded_at ? displayDate(payment.recorded_at) : "Historical balance; payment date unavailable"}</p></div>
          <p className="font-semibold tabular-nums">{money(payment.amount)}</p>
        </li>)}</ul>
      </section> : null}
      {invoice.notes ? <section><h2 className="font-semibold">Notes</h2><p className="mt-2 whitespace-pre-wrap break-words text-ink-600">{invoice.notes}</p></section> : null}
      <footer className="space-y-4 border-t border-ink-200 pt-6 text-sm text-ink-600">
        <p>Questions about this invoice? Contact {company.name}{company.email ? ` at ${company.email}` : company.phone ? ` at ${company.phone}` : " directly"}.</p>
        <PrintInvoice />
      </footer>
    </article>
  </main>;
}
