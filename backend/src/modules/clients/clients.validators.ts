import { z } from "zod";

const trimmedString = (max: number) =>
  z
    .string()
    .max(max)
    .transform((value) => value.trim());

const optionalText = (max: number) =>
  z
    .string()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => {
      if (value === null || value === undefined) return value;
      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    });

const optionalEmail = z
  .string()
  .max(255)
  .nullable()
  .optional()
  .transform((value, ctx) => {
    if (value === null || value === undefined) return value;
    const trimmed = value.trim().toLowerCase();
    if (trimmed.length === 0) return null;
    const result = z.string().email().safeParse(trimmed);
    if (!result.success) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Invalid email address",
      });
      return z.NEVER;
    }
    return trimmed;
  });

export const createClientSchema = z.object({
  name: trimmedString(255).refine((value) => value.length >= 1, {
    message: "Name is required",
  }),
  email: optionalEmail,
  phone: optionalText(50),
  address: optionalText(500),
  city: optionalText(100),
  state: optionalText(100),
  zip: optionalText(20),
  notes: optionalText(5000),
});

export const updateClientSchema = z.object({
  name: trimmedString(255)
    .refine((value) => value.length >= 1, { message: "Name is required" })
    .optional(),
  email: optionalEmail,
  phone: optionalText(50),
  address: optionalText(500),
  city: optionalText(100),
  state: optionalText(100),
  zip: optionalText(20),
  notes: optionalText(5000),
});

export type CreateClientInput = z.infer<typeof createClientSchema>;
export type UpdateClientInput = z.infer<typeof updateClientSchema>;
