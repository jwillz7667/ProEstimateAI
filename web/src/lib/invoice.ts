import { fetchAPI } from "./api";

export interface SharedInvoice {
  invoice: {
    invoice_number: string; status: string; subtotal: number; tax_amount: number;
    discount_amount: number; total_amount: number; amount_paid: number; amount_due: number;
    currency_code: string | null; issued_date: string | null; due_date: string | null;
    notes: string | null; payment_instructions: string | null;
  };
  company: { name: string; logo_url: string | null; primary_color: string | null; email: string | null; phone: string | null };
  client: { name: string }; project: { title: string };
  line_items: Array<{ name: string; description: string | null; quantity: number; unit: string; unit_cost: number; line_total: number }>;
  payments: Array<{ id: string; amount: number; method: string; recorded_at: string | null; created_at: string }>;
  installments: Array<{ id: string; title: string; amount: number; paid_amount: number; amount_due: number; due_date: string | null }>;
  online_payment?: { available: boolean; processing: boolean; requires_contractor_review: boolean; test_mode?: boolean };
}

export function getSharedInvoice(token: string): Promise<SharedInvoice> {
  return fetchAPI(`/invoice-share/${encodeURIComponent(token)}`);
}

export function invoiceMoney(amount: number, currency: string | null): string {
  const code = currency && /^[A-Z]{3}$/.test(currency.toUpperCase()) ? currency.toUpperCase() : "USD";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: code }).format(amount);
}

export function paymentMethodLabel(method: string): string {
  const labels: Record<string, string> = {
    cash: "Cash", check: "Check", bank_transfer: "Bank transfer", other: "Other payment",
    opening_balance: "Previous recorded balance", legacy_manual: "Recorded payment",
    balance_correction: "Balance correction", stripe: "Online payment",
    stripe_refund: "Online payment refund",
  };
  return labels[method] ?? "Recorded payment";
}
