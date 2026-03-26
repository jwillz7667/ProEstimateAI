import { z } from 'zod';

// ─── Signup ──────────────────────────────────────────────────────────────────
export const signupSchema = z.object({
  full_name: z
    .string()
    .trim()
    .min(2, 'Full name must be at least 2 characters')
    .max(100, 'Full name must not exceed 100 characters'),
  email: z
    .string()
    .trim()
    .email('Invalid email address')
    .max(255, 'Email must not exceed 255 characters')
    .transform((v) => v.toLowerCase()),
  company_name: z
    .string()
    .trim()
    .min(2, 'Company name must be at least 2 characters')
    .max(200, 'Company name must not exceed 200 characters'),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .max(128, 'Password must not exceed 128 characters')
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/,
      'Password must contain at least one uppercase letter, one lowercase letter, and one digit',
    ),
});

export type SignupInput = z.infer<typeof signupSchema>;

// ─── Login ───────────────────────────────────────────────────────────────────
export const loginSchema = z.object({
  email: z
    .string()
    .trim()
    .email('Invalid email address')
    .max(255, 'Email must not exceed 255 characters')
    .transform((v) => v.toLowerCase()),
  password: z
    .string()
    .min(1, 'Password is required')
    .max(128, 'Password must not exceed 128 characters'),
});

export type LoginInput = z.infer<typeof loginSchema>;

// ─── Refresh ─────────────────────────────────────────────────────────────────
export const refreshSchema = z.object({
  refresh_token: z
    .string()
    .min(1, 'Refresh token is required'),
});

export type RefreshInput = z.infer<typeof refreshSchema>;

// ─── Logout ──────────────────────────────────────────────────────────────────
export const logoutSchema = z.object({
  refresh_token: z
    .string()
    .min(1, 'Refresh token is required')
    .optional(),
});

export type LogoutInput = z.infer<typeof logoutSchema>;
