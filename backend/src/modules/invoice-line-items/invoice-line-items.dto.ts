import { InvoiceLineItem } from '@prisma/client';

export interface InvoiceLineItemDto {
  id: string;
  invoice_id: string;
  name: string;
  description: string | null;
  quantity: number;
  unit: string;
  unit_cost: number;
  line_total: number;
  sort_order: number;
}

export function toInvoiceLineItemDto(item: InvoiceLineItem): InvoiceLineItemDto {
  return {
    id: item.id,
    invoice_id: item.invoiceId,
    name: item.name,
    description: item.description,
    quantity: Number(item.quantity),
    unit: item.unit,
    unit_cost: Number(item.unitCost),
    line_total: Number(item.lineTotal),
    sort_order: item.sortOrder,
  };
}
