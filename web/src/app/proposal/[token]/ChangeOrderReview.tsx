import { changeOrderBillingExplanation, formatCurrency, formatQuantity, type ChangeOrderComparison } from "@/lib/proposal";

export function ChangeOrderReview({ comparison }: { comparison: ChangeOrderComparison }) {
  const signed = (value: number) => `${value > 0 ? "+" : value < 0 ? "−" : ""}${formatCurrency(Math.abs(value))}`;
  return (
    <section className="mb-10 rounded-2xl border border-ink-200 bg-white p-5 sm:p-6" aria-labelledby="change-order-title">
      <p className="text-xs font-semibold uppercase tracking-wider text-ink-500">Change to your approved contract</p>
      <h2 id="change-order-title" className="mt-2 text-xl font-semibold text-ink-950">{comparison.title}</h2>
      <p className="mt-3 whitespace-pre-line leading-relaxed text-ink-700">{comparison.reason}</p>
      <dl className="mt-6 space-y-3 text-sm">
        <Row label="Previously approved total" value={formatCurrency(comparison.base_total)} />
        <Row label="Revised contract total" value={formatCurrency(comparison.new_total)} />
        <div className="flex items-baseline justify-between gap-4 border-t border-ink-200 pt-4 text-base font-semibold text-ink-950">
          <dt>{comparison.change_amount < 0 ? "Contract reduction" : comparison.change_amount > 0 ? "Contract increase" : "Price change"}</dt>
          <dd className="shrink-0 tabular-nums">{signed(comparison.change_amount)}</dd>
        </div>
      </dl>
      <p className="mt-4 text-sm leading-relaxed text-ink-700">{changeOrderBillingExplanation(comparison)}</p>
      <details data-print-expand className="mt-5 rounded-xl border border-ink-100 p-4">
        <summary className="cursor-pointer text-sm font-medium text-ink-900">Review the previous scope and price changes</summary>
        <p className="mt-4 text-xs text-ink-500">{comparison.base_estimate_number} · Version {comparison.base_version}</p>
        <h3 className="mt-3 text-sm font-semibold text-ink-950">Previously approved scope</h3>
        <ul className="mt-2 divide-y divide-ink-100">
          {comparison.base_scope.line_items.map((item, index) => (
            <li key={index} className="flex items-start justify-between gap-4 py-3 text-sm">
              <div className="min-w-0"><p className="break-words text-ink-900">{item.name}</p>{item.description && <p className="mt-1 whitespace-pre-line text-ink-600">{item.description}</p>}<p className="mt-1 text-xs text-ink-500">{formatQuantity(item.quantity)} {item.unit}</p></div>
              <p className="shrink-0 tabular-nums text-ink-900">{formatCurrency(item.line_total)}</p>
            </li>
          ))}
        </ul>
        {comparison.base_scope.assumptions && <p className="mt-3 whitespace-pre-line text-sm text-ink-600"><strong>Previous assumptions:</strong> {comparison.base_scope.assumptions}</p>}
        {comparison.base_scope.exclusions && <p className="mt-3 whitespace-pre-line text-sm text-ink-600"><strong>Previous exclusions:</strong> {comparison.base_scope.exclusions}</p>}
        <dl className="mt-4 space-y-2 border-t border-ink-100 pt-4 text-sm">
          <Row label="Subtotal change" value={signed(comparison.subtotal_delta)} />
          <Row label="Tax change" value={signed(comparison.tax_delta)} />
          <Row label="Discount change (deducted)" value={signed(comparison.discount_delta)} />
        </dl>
      </details>
      <p className="mt-4 text-xs text-ink-500">Review the complete revised scope, price and terms below before approving this change.</p>
    </section>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return <div className="flex items-baseline justify-between gap-4"><dt className="text-ink-600">{label}</dt><dd className="shrink-0 tabular-nums text-ink-900">{value}</dd></div>;
}
