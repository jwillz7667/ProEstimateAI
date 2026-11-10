import { z } from "zod";
import { Prisma } from "@prisma/client";

const decimal = z.number().finite().positive().max(9999999999.99)
  .refine((value) => new Prisma.Decimal(value).decimalPlaces() <= 2, "Use at most two decimal places");
export const createJobCostSchema = z.object({
  request_id: z.string().uuid(), category: z.enum(["materials", "labor", "other"]),
  description: z.string().trim().min(1).max(500), amount: decimal.optional(),
  currency_code: z.string().regex(/^[A-Za-z]{3}$/).transform((value) => value.toUpperCase()).default("USD"),
  labor_hours: decimal.max(100000).optional(), hourly_rate: decimal.optional(),
  recorded_at: z.string().datetime(),
}).strict().superRefine((value, ctx) => {
  if ((value.labor_hours !== undefined) !== (value.hourly_rate !== undefined)) ctx.addIssue({ code: "custom", message: "Enter both hours and hourly cost" });
  if (value.category !== "labor" && value.labor_hours !== undefined) ctx.addIssue({ code: "custom", message: "Hours apply to labor costs only" });
  if (value.amount === undefined && value.labor_hours === undefined) ctx.addIssue({ code: "custom", message: "Enter a cost amount" });
});
export const uploadJobReceiptSchema = z.object({
  data_base64: z.string().min(1).max(7_000_000),
  mime_type: z.enum(["application/pdf", "image/jpeg", "image/png"]),
  filename: z.string().min(1).max(255),
}).strict();
export type CreateJobCostInput = z.infer<typeof createJobCostSchema>;
export type UploadJobReceiptInput = z.infer<typeof uploadJobReceiptSchema>;
