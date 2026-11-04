import { z } from "zod";
import { Prisma } from "@prisma/client";

const money = z.number().finite().positive().max(9999999999.99)
  .refine((value) => new Prisma.Decimal(value).decimalPlaces() <= 2, "Use no more than two decimal places");

export const recordInvoicePaymentSchema = z.object({
  request_id: z.string().uuid(),
  amount: money,
  method: z.enum(["cash", "check", "bank_transfer", "other"]),
  reference: z.string().trim().max(255).nullable().optional(),
  notes: z.string().trim().max(2000).nullable().optional(),
  recorded_at: z.string().datetime().optional(),
}).strict();

export const invoiceScheduleSchema = z.object({
  expected_total: money,
  installments: z.array(z.object({
    title: z.string().trim().min(1).max(120),
    amount: money,
    due_date: z.string().datetime().nullable().optional(),
  }).strict()).min(1).max(24),
}).strict();

export type RecordInvoicePaymentInput = z.infer<typeof recordInvoicePaymentSchema>;
export type InvoiceScheduleInput = z.infer<typeof invoiceScheduleSchema>;
