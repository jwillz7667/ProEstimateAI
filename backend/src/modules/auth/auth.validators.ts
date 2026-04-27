import { z } from "zod";

// ─── Signup ──────────────────────────────────────────────────────────────────
export const signupSchema = z.object({
  full_name: z
    .string()
    .trim()
    .min(2, "Full name must be at least 2 characters")
    .max(100, "Full name must not exceed 100 characters"),
  email: z
    .string()
    .trim()
    .email("Invalid email address")
    .max(255, "Email must not exceed 255 characters")
    .transform((v) => v.toLowerCase()),
  company_name: z
    .string()
    .trim()
    .min(2, "Company name must be at least 2 characters")
    .max(200, "Company name must not exceed 200 characters"),
  password: z
    .string()
    .min(8, "Password must be at least 8 characters")
    .max(128, "Password must not exceed 128 characters")
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/,
      "Password must contain at least one uppercase letter, one lowercase letter, and one digit",
    ),
});

export type SignupInput = z.infer<typeof signupSchema>;

// ─── Login ───────────────────────────────────────────────────────────────────
export const loginSchema = z.object({
  email: z
    .string()
    .trim()
    .email("Invalid email address")
    .max(255, "Email must not exceed 255 characters")
    .transform((v) => v.toLowerCase()),
  password: z
    .string()
    .min(1, "Password is required")
    .max(128, "Password must not exceed 128 characters"),
});

export type LoginInput = z.infer<typeof loginSchema>;

// ─── Refresh ─────────────────────────────────────────────────────────────────
export const refreshSchema = z.object({
  refresh_token: z.string().min(1, "Refresh token is required"),
});

export type RefreshInput = z.infer<typeof refreshSchema>;

// ─── Apple Sign In ──────────────────────────────────────────────────────────
export const appleSignInSchema = z.object({
  identity_token: z.string().min(1, "Identity token is required"),
  authorization_code: z.string().min(1, "Authorization code is required"),
  full_name: z.string().trim().max(100).optional().nullable(),
  email: z
    .string()
    .email()
    .max(255)
    .optional()
    .nullable()
    .transform((v) => v?.toLowerCase()),
});

export type AppleSignInInput = z.infer<typeof appleSignInSchema>;

// ─── Google Sign In ─────────────────────────────────────────────────────────
// The iOS client gives us the Google ID token (a JWT signed by Google's
// JWKS). The backend verifies it against `GOOGLE_OAUTH_*_CLIENT_ID` and
// either logs the matching user in or provisions a new Company + User on
// first sight. `full_name` and `email` are optional — Google supplies
// them in the token claims, but the iOS layer can override (e.g. when
// the user edits their name during sign-up).
export const googleSignInSchema = z.object({
  identity_token: z.string().min(1, "Identity token is required"),
  full_name: z.string().trim().max(100).optional().nullable(),
  email: z
    .string()
    .email()
    .max(255)
    .optional()
    .nullable()
    .transform((v) => v?.toLowerCase()),
});

export type GoogleSignInInput = z.infer<typeof googleSignInSchema>;

// ─── Logout ──────────────────────────────────────────────────────────────────
export const logoutSchema = z.object({
  refresh_token: z.string().min(1, "Refresh token is required").optional(),
});

export type LogoutInput = z.infer<typeof logoutSchema>;

// ─── Forgot Password ────────────────────────────────────────────────────────
export const forgotPasswordSchema = z.object({
  email: z
    .string()
    .trim()
    .email("Invalid email address")
    .max(255, "Email must not exceed 255 characters")
    .transform((v) => v.toLowerCase()),
});

export type ForgotPasswordInput = z.infer<typeof forgotPasswordSchema>;

// ─── Reset Password ─────────────────────────────────────────────────────────
export const resetPasswordSchema = z.object({
  token: z.string().min(1, "Reset token is required"),
  new_password: z
    .string()
    .min(8, "Password must be at least 8 characters")
    .max(128, "Password must not exceed 128 characters")
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/,
      "Password must contain at least one uppercase letter, one lowercase letter, and one digit",
    ),
});

export type ResetPasswordInput = z.infer<typeof resetPasswordSchema>;
