import { z } from "zod";

const projectTypeEnum = z.enum([
  "kitchen",
  "bathroom",
  "flooring",
  "roofing",
  "painting",
  "siding",
  "room_remodel",
  "exterior",
  "landscaping",
  "lawn_care",
  "custom",
]);

const projectStatusEnum = z.enum([
  "draft",
  "photos_uploaded",
  "generating",
  "generation_complete",
  "estimate_created",
  "proposal_sent",
  "approved",
  "declined",
  "invoiced",
  "completed",
  "archived",
]);

const qualityTierEnum = z.enum(["standard", "premium", "luxury"]);

// Property measurements — written by the maps integration once the
// contractor saves a polygon (lawn) or accepts the Solar API roof segment
// report. Caps are generous: a 50,000-sq-ft estate lawn or commercial
// HOA common area still fits, while staying tight enough to reject
// nonsense like 9-figure values.
const lawnAreaField = z.number().min(0).max(5_000_000).nullable().optional();
const roofAreaField = z.number().min(0).max(500_000).nullable().optional();
const latitudeField = z.number().min(-90).max(90).nullable().optional();
const longitudeField = z.number().min(-180).max(180).nullable().optional();

// Recurring contract terms (LAWN_CARE primarily). Frequency is a closed
// set we accept; storing as text in Postgres lets us evolve without an
// enum migration each time we add a cadence.
const recurrenceFrequencyEnum = z.enum([
  "weekly",
  "biweekly",
  "monthly",
  "quarterly",
  "seasonal",
]);
const visitsPerMonthField = z.number().min(0).max(60).nullable().optional();
const contractMonthsField = z
  .number()
  .int()
  .min(1)
  .max(120)
  .nullable()
  .optional();
const recurrenceStartDateField = z.string().datetime().nullable().optional();

export const createProjectSchema = z.object({
  title: z.string().min(1).max(255),
  client_id: z.string().cuid().nullable().optional(),
  description: z.string().max(5000).nullable().optional(),
  project_type: projectTypeEnum.optional(),
  status: projectStatusEnum.optional(),
  budget_min: z.number().min(0).nullable().optional(),
  budget_max: z.number().min(0).nullable().optional(),
  quality_tier: qualityTierEnum.optional(),
  square_footage: z.number().min(0).nullable().optional(),
  dimensions: z.string().max(500).nullable().optional(),
  language: z.string().max(10).nullable().optional(),
  lawn_area_sq_ft: lawnAreaField,
  roof_area_sq_ft: roofAreaField,
  property_latitude: latitudeField,
  property_longitude: longitudeField,
  is_recurring: z.boolean().optional(),
  recurrence_frequency: recurrenceFrequencyEnum.nullable().optional(),
  visits_per_month: visitsPerMonthField,
  contract_months: contractMonthsField,
  recurrence_start_date: recurrenceStartDateField,
});

export const updateProjectSchema = z.object({
  title: z.string().min(1).max(255).optional(),
  client_id: z.string().cuid().nullable().optional(),
  description: z.string().max(5000).nullable().optional(),
  project_type: projectTypeEnum.optional(),
  status: projectStatusEnum.optional(),
  budget_min: z.number().min(0).nullable().optional(),
  budget_max: z.number().min(0).nullable().optional(),
  quality_tier: qualityTierEnum.optional(),
  square_footage: z.number().min(0).nullable().optional(),
  dimensions: z.string().max(500).nullable().optional(),
  language: z.string().max(10).nullable().optional(),
  lawn_area_sq_ft: lawnAreaField,
  roof_area_sq_ft: roofAreaField,
  property_latitude: latitudeField,
  property_longitude: longitudeField,
  is_recurring: z.boolean().optional(),
  recurrence_frequency: recurrenceFrequencyEnum.nullable().optional(),
  visits_per_month: visitsPerMonthField,
  contract_months: contractMonthsField,
  recurrence_start_date: recurrenceStartDateField,
});

export type CreateProjectInput = z.infer<typeof createProjectSchema>;
export type UpdateProjectInput = z.infer<typeof updateProjectSchema>;
