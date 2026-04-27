import { z } from "zod";

const latitudeField = z.number().min(-90).max(90);
const longitudeField = z.number().min(-180).max(180);

export const geocodeSchema = z.object({
  address: z.string().min(3).max(500),
});

export const lawnAreaSchema = z.object({
  // 3 vertices is the minimum to bound an area; cap at 200 to prevent
  // pathological clients from sending megabyte payloads.
  polygon: z
    .array(
      z.object({
        latitude: latitudeField,
        longitude: longitudeField,
      }),
    )
    .min(3)
    .max(200),
  // Optional project to write the measurement back to. When provided,
  // the controller PATCHes the project's lawn_area_sq_ft + lat/lng (the
  // polygon centroid).
  project_id: z.string().cuid().optional(),
});

// Caller can either pass a known lat/lng (from a prior geocode call /
// from a tap on the lawn map) or a free-form address we'll geocode
// internally. Exactly one of `address` or `latitude`+`longitude` is
// required.
export const roofScoutingSchema = z
  .object({
    address: z.string().min(3).max(500).optional(),
    latitude: latitudeField.optional(),
    longitude: longitudeField.optional(),
    project_id: z.string().cuid().optional(),
  })
  .refine(
    (data) =>
      Boolean(data.address) ||
      (data.latitude !== undefined && data.longitude !== undefined),
    {
      message: "Either address or latitude+longitude must be provided",
    },
  );

export const staticMapQuerySchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
  zoom: z.coerce.number().int().min(1).max(21).default(19),
  width: z.coerce.number().int().min(64).max(640).default(640),
  height: z.coerce.number().int().min(64).max(640).default(400),
  maptype: z
    .enum(["satellite", "roadmap", "hybrid", "terrain"])
    .default("satellite"),
  retina: z
    .union([z.literal("true"), z.literal("false"), z.boolean()])
    .default("true")
    .transform((v) => v === true || v === "true"),
});

export type GeocodeInput = z.infer<typeof geocodeSchema>;
export type LawnAreaInput = z.infer<typeof lawnAreaSchema>;
export type RoofScoutingInput = z.infer<typeof roofScoutingSchema>;
export type StaticMapQuery = z.infer<typeof staticMapQuerySchema>;
