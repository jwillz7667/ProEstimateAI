import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  CORS_ORIGIN: z.string().default("*"),
  GOOGLE_AI_API_KEY: z.string().min(1).optional(),
  DEEPSEEK_API_KEY: z.string().min(1).optional(),
  PIAPI_API_KEY: z.string().min(1).optional(),
  ADMIN_EMAILS: z.string().optional().default(""),
  GOOGLE_PLACES_API_KEY: z.string().min(1).optional(),
  // Single Google Cloud API key with Geocoding API, Maps Static API, and
  // Solar API (Building Insights) enabled. Used by src/lib/google-maps.ts
  // for lawn polygon geocoding, roof scouting, and the static-map proxy.
  GOOGLE_MAPS_API_KEY: z.string().min(1).optional(),
  // Google OAuth Client IDs. The iOS app obtains an ID token signed for
  // the iOS client; the backend then validates it accepting either client
  // ID as a valid `aud` (so a future Next.js web app can share this
  // backend without a separate verifier path).
  GOOGLE_OAUTH_IOS_CLIENT_ID: z.string().min(1).optional(),
  GOOGLE_OAUTH_WEB_CLIENT_ID: z.string().min(1).optional(),
  RESEND_API_KEY: z.string().min(1).optional(),
  SERPAPI_API_KEY: z.string().min(1).optional(),
  REDIS_URL: z.string().url().optional(),
  RESEND_FROM_EMAIL: z
    .string()
    .default("ProEstimate AI <noreply@proestimateai.com>"),
  API_BASE_URL: z
    .string()
    .default("https://proestimate-api-production.up.railway.app"),
  APP_STORE_ISSUER_ID: z.string().optional(),
});

function loadEnv() {
  const result = envSchema.safeParse(process.env);
  if (!result.success) {
    console.error(
      "Invalid environment variables:",
      result.error.flatten().fieldErrors,
    );
    process.exit(1);
  }
  return result.data;
}

export const env = loadEnv();
