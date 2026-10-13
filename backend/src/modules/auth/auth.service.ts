import crypto from "crypto";
import { env } from "../../config/env";
import { prisma } from "../../config/database";
import { hashPassword, verifyPassword } from "../../lib/hash";
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
  type JwtPayload,
} from "../../lib/jwt";
import { generateId } from "../../lib/id";
import {
  AuthenticationError,
  ConflictError,
  ValidationError,
} from "../../lib/errors";
import {
  FREE_TIER_AI_GENERATION_CREDITS,
  STARTER_CREDITS_SOURCE,
} from "../../lib/limits";
import { verifyAppleIdentityToken } from "../../lib/apple-auth";
import {
  verifyGoogleIdentityToken,
  GoogleAuthNotConfiguredError,
} from "../../lib/google-auth";
import type { User, Company } from "@prisma/client";
import type {
  SignupInput,
  LoginInput,
  AppleSignInInput,
  GoogleSignInInput,
  ForgotPasswordInput,
  ResetPasswordInput,
} from "./auth.validators";

// ─── Result types ────────────────────────────────────────────────────────────

export interface AuthResult {
  user: User;
  company: Company;
  accessToken: string;
  refreshToken: string;
}

export interface TokenPairResult {
  accessToken: string;
  refreshToken: string;
}

// ─── Signup ──────────────────────────────────────────────────────────────────

export async function signup(input: SignupInput): Promise<AuthResult> {
  // 1. Check email uniqueness
  const existingUser = await prisma.user.findUnique({
    where: { email: input.email },
  });
  if (existingUser) {
    throw new ConflictError("A user with this email already exists");
  }

  // 2. Hash password
  const passwordHash = await hashPassword(input.password);

  // 3. Look up the FREE_STARTER plan (must exist from seed)
  const freePlan = await prisma.plan.findUniqueOrThrow({
    where: { code: "FREE_STARTER" },
  });

  // 4. Create Company + User + Entitlement + UsageBuckets in a single transaction
  const userId = generateId();
  const companyId = generateId();

  const { user, company } = await prisma.$transaction(async (tx) => {
    const createdCompany = await tx.company.create({
      data: {
        id: companyId,
        name: input.company_name,
      },
    });

    const createdUser = await tx.user.create({
      data: {
        id: userId,
        companyId: createdCompany.id,
        email: input.email,
        passwordHash,
        fullName: input.full_name,
        role: "OWNER",
      },
    });

    // Create FREE entitlement
    await tx.userEntitlement.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        planId: freePlan.id,
        status: "FREE",
      },
    });

    // Seed AI generation starter credits. Lets the user try the core
    // product loop a fixed number of times before the paywall fires.
    await tx.usageBucket.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        metricCode: "AI_GENERATION",
        includedQuantity: FREE_TIER_AI_GENERATION_CREDITS,
        consumedQuantity: 0,
        source: STARTER_CREDITS_SOURCE,
      },
    });

    return { user: createdUser, company: createdCompany };
  });

  // 5. Sign tokens
  const jwtPayload: JwtPayload = { userId: user.id, companyId: company.id };
  const accessToken = signAccessToken(jwtPayload);
  const refreshToken = signRefreshToken(jwtPayload);

  // 6. Store refresh token in DB (30-day expiry)
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return { user, company, accessToken, refreshToken };
}

// ─── Login ───────────────────────────────────────────────────────────────────

export async function login(input: LoginInput): Promise<AuthResult> {
  // 1. Find user by email, include company
  const user = await prisma.user.findUnique({
    where: { email: input.email },
    include: { company: true },
  });

  if (!user) {
    // Generic message to prevent email enumeration
    throw new AuthenticationError("Invalid email or password");
  }

  // 2. Verify password (Apple-only users have no password)
  if (!user.passwordHash) {
    throw new AuthenticationError(
      "This account uses Sign in with Apple. Please sign in with Apple instead.",
    );
  }
  const passwordValid = await verifyPassword(input.password, user.passwordHash);
  if (!passwordValid) {
    throw new AuthenticationError("Invalid email or password");
  }

  // 3. Check account is active
  if (!user.isActive) {
    throw new AuthenticationError("Account is deactivated");
  }

  // 4. Sign tokens
  const jwtPayload: JwtPayload = { userId: user.id, companyId: user.companyId };
  const accessToken = signAccessToken(jwtPayload);
  const refreshToken = signRefreshToken(jwtPayload);

  // 5. Store refresh token
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return { user, company: user.company, accessToken, refreshToken };
}

// ─── Apple Sign In ──────────────────────────────────────────────────────────

export async function appleSignIn(
  input: AppleSignInInput,
): Promise<AuthResult> {
  // 1. Verify the identity token with Apple's JWKS
  const claims = await verifyAppleIdentityToken(input.identity_token);
  const appleUserId = claims.sub;
  // Only signed, verified provider claims may identify an account. The
  // client email is display metadata and must never authorize account linking.
  const email = (claims.email_verified === true || claims.email_verified === "true")
    ? claims.email?.trim().toLowerCase()
    : undefined;

  // 2. Look for existing user by appleUserId
  let user = await prisma.user.findUnique({
    where: { appleUserId },
    include: { company: true },
  });

  if (user) {
    // Existing Apple user — issue tokens (login flow)
    if (!user.isActive) {
      throw new AuthenticationError("Account is deactivated");
    }

    const jwtPayload: JwtPayload = {
      userId: user.id,
      companyId: user.companyId,
    };
    const accessToken = signAccessToken(jwtPayload);
    const refreshToken = signRefreshToken(jwtPayload);

    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        token: refreshToken,
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });

    return { user, company: user.company, accessToken, refreshToken };
  }

  if (!email) {
    throw new AuthenticationError("Apple account email not provided or unverified");
  }

  // 3. Check by verified email — link appleUserId to existing account
  if (email) {
    const existingUser = await prisma.user.findUnique({
      where: { email: email.toLowerCase() },
      include: { company: true },
    });

    if (existingUser) {
      if (!existingUser.isActive ||
          (existingUser.appleUserId && existingUser.appleUserId !== appleUserId)) {
        throw new AuthenticationError("Unable to sign in with this Apple account");
      }
      // Link Apple ID to existing user
      const updated = await prisma.user.update({
        where: { id: existingUser.id },
        data: { appleUserId },
        include: { company: true },
      });

      const jwtPayload: JwtPayload = {
        userId: updated.id,
        companyId: updated.companyId,
      };
      const accessToken = signAccessToken(jwtPayload);
      const refreshToken = signRefreshToken(jwtPayload);

      await prisma.refreshToken.create({
        data: {
          userId: updated.id,
          token: refreshToken,
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        },
      });

      return {
        user: updated,
        company: updated.company,
        accessToken,
        refreshToken,
      };
    }
  }

  // 4. Brand new user — create Company + User + Entitlement + UsageBuckets
  const fullName = input.full_name || email?.split("@")[0] || "Apple User";
  const userEmail =
    email?.toLowerCase() ||
    `apple_${appleUserId.substring(0, 8)}@proestimate.app`;

  const freePlan = await prisma.plan.findUniqueOrThrow({
    where: { code: "FREE_STARTER" },
  });

  const userId = generateId();
  const companyId = generateId();

  const { user: newUser, company } = await prisma.$transaction(async (tx) => {
    const createdCompany = await tx.company.create({
      data: {
        id: companyId,
        name: `${fullName}'s Company`,
      },
    });

    const createdUser = await tx.user.create({
      data: {
        id: userId,
        companyId: createdCompany.id,
        email: userEmail,
        fullName,
        appleUserId,
        role: "OWNER",
      },
    });

    await tx.userEntitlement.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        planId: freePlan.id,
        status: "FREE",
      },
    });

    // Seed AI generation starter credits — same allowance as the
    // email-signup path so first-tap parity holds across providers.
    await tx.usageBucket.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        metricCode: "AI_GENERATION",
        includedQuantity: FREE_TIER_AI_GENERATION_CREDITS,
        consumedQuantity: 0,
        source: STARTER_CREDITS_SOURCE,
      },
    });

    return { user: createdUser, company: createdCompany };
  });

  const jwtPayload: JwtPayload = { userId: newUser.id, companyId: company.id };
  const accessToken = signAccessToken(jwtPayload);
  const refreshToken = signRefreshToken(jwtPayload);

  await prisma.refreshToken.create({
    data: {
      userId: newUser.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return { user: newUser, company, accessToken, refreshToken };
}

// ─── Google Sign In ─────────────────────────────────────────────────────────

export async function googleSignIn(
  input: GoogleSignInInput,
): Promise<AuthResult> {
  // 1. Verify Google's identity token (signature + iss + aud).
  // GoogleAuthNotConfiguredError leaks through unchanged so the route
  // can surface a 503; AuthenticationError covers everything else.
  const claims = await verifyGoogleIdentityToken(input.identity_token).catch(
    (err) => {
      if (err instanceof GoogleAuthNotConfiguredError) throw err;
      throw err;
    },
  );

  const googleId = claims.sub;
  const email = claims.emailVerified ? claims.email?.trim().toLowerCase() : undefined;

  // 2. Look for an existing user already linked to this Google account.
  let user = await prisma.user.findUnique({
    where: { googleId },
    include: { company: true },
  });

  if (user) {
    if (!user.isActive) {
      throw new AuthenticationError("Account is deactivated");
    }
    return await issueTokens(user);
  }

  if (!email) {
    throw new AuthenticationError("Google account email not provided or unverified");
  }

  // 3. Match by verified email — link Google ID onto an existing email/password
  // account so a user who signed up with a password can later use
  // "Continue with Google" without losing their data.
  if (email) {
    const existingUser = await prisma.user.findUnique({
      where: { email },
      include: { company: true },
    });
    if (existingUser) {
      // Google is not authoritative for third-party email addresses without
      // a Workspace hosted-domain claim, even if email_verified is true.
      // Such users must authenticate the existing account before linking.
      const authoritativeEmail = email.endsWith("@gmail.com") || Boolean(claims.hostedDomain);
      if (!authoritativeEmail) {
        throw new AuthenticationError("Sign in to your existing account to link Google");
      }
      if (!existingUser.isActive ||
          (existingUser.googleId && existingUser.googleId !== googleId)) {
        throw new AuthenticationError("Unable to sign in with this Google account");
      }
      const updated = await prisma.user.update({
        where: { id: existingUser.id },
        data: { googleId },
        include: { company: true },
      });
      return await issueTokens(updated);
    }
  }

  // 4. Brand new user — create Company + User + free entitlement +
  // starter usage buckets. Same shape as the Apple sign-in flow above.
  const fullName =
    input.full_name?.trim() ||
    claims.name ||
    [claims.givenName, claims.familyName].filter(Boolean).join(" ").trim() ||
    email?.split("@")[0] ||
    "Google User";
  const userEmail =
    email || `google_${googleId.substring(0, 8)}@proestimate.app`;

  const freePlan = await prisma.plan.findUniqueOrThrow({
    where: { code: "FREE_STARTER" },
  });

  const userId = generateId();
  const companyId = generateId();

  const { user: newUser, company } = await prisma.$transaction(async (tx) => {
    const createdCompany = await tx.company.create({
      data: {
        id: companyId,
        name: `${fullName}'s Company`,
      },
    });

    const createdUser = await tx.user.create({
      data: {
        id: userId,
        companyId: createdCompany.id,
        email: userEmail,
        fullName,
        googleId,
        avatarUrl: claims.picture ?? null,
        role: "OWNER",
      },
    });

    await tx.userEntitlement.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        planId: freePlan.id,
        status: "FREE",
      },
    });

    // Seed AI generation starter credits — same allowance as the
    // email + Apple paths so first-tap parity holds across providers.
    await tx.usageBucket.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        metricCode: "AI_GENERATION",
        includedQuantity: FREE_TIER_AI_GENERATION_CREDITS,
        consumedQuantity: 0,
        source: STARTER_CREDITS_SOURCE,
      },
    });

    return { user: createdUser, company: createdCompany };
  });

  return await issueTokens({ ...newUser, company });
}

/**
 * Mint a fresh access + refresh token pair for `user`. Persists the
 * refresh token so it can be rotated on subsequent /v1/auth/refresh
 * calls. Used by both the Apple and Google sign-in flows.
 */
async function issueTokens(
  user: User & { company: Company },
): Promise<AuthResult> {
  const jwtPayload: JwtPayload = { userId: user.id, companyId: user.companyId };
  const accessToken = signAccessToken(jwtPayload);
  const refreshToken = signRefreshToken(jwtPayload);
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      token: refreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });
  return {
    user,
    company: user.company,
    accessToken,
    refreshToken,
  };
}

// ─── Refresh ─────────────────────────────────────────────────────────────────

export async function refresh(
  refreshTokenValue: string,
): Promise<TokenPairResult> {
  // 1. Verify the JWT signature and expiry
  let payload: JwtPayload;
  try {
    payload = verifyRefreshToken(refreshTokenValue);
  } catch {
    throw new AuthenticationError("Invalid or expired refresh token");
  }

  // 2. Look up the token in DB (must exist and not be expired)
  const storedToken = await prisma.refreshToken.findUnique({
    where: { token: refreshTokenValue },
  });

  if (!storedToken) {
    // Token was revoked or never existed -- possible token reuse attack.
    // Revoke all refresh tokens for this user as a precaution.
    await prisma.refreshToken.deleteMany({
      where: { userId: payload.userId },
    });
    throw new AuthenticationError("Refresh token has been revoked");
  }

  if (storedToken.expiresAt < new Date()) {
    // Clean up expired token (deleteMany avoids P2025 on concurrent requests)
    await prisma.refreshToken.deleteMany({ where: { id: storedToken.id } });
    throw new AuthenticationError("Refresh token has expired");
  }

  // Resolve current membership instead of trusting a possibly stale JWT.
  const user = await prisma.user.findUnique({ where: { id: payload.userId } });
  if (!user?.isActive || storedToken.userId !== payload.userId) {
    throw new AuthenticationError("Account is unavailable");
  }

  // Consume once and create the successor atomically. A concurrent request
  // that lost the delete race must never mint a second valid session.
  return prisma.$transaction(async (tx) => {
    const consumed = await tx.refreshToken.deleteMany({
      where: { id: storedToken.id, expiresAt: { gt: new Date() } },
    });
    if (consumed.count !== 1) {
      throw new AuthenticationError("Refresh token has been revoked");
    }
    const jwtPayload: JwtPayload = { userId: user.id, companyId: user.companyId };
    const accessToken = signAccessToken(jwtPayload);
    const refreshToken = signRefreshToken(jwtPayload);
    await tx.refreshToken.create({
      data: {
        userId: user.id,
        token: refreshToken,
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
    return { accessToken, refreshToken };
  });
}

// ─── Logout ──────────────────────────────────────────────────────────────────

export async function logout(
  userId: string | undefined,
  refreshTokenValue: string | undefined,
): Promise<void> {
  if (refreshTokenValue) {
    // Revoke the specific refresh token
    await prisma.refreshToken.deleteMany({
      where: { token: refreshTokenValue },
    });
  } else if (userId) {
    // If no token provided but user is authenticated, revoke all their tokens
    await prisma.refreshToken.deleteMany({
      where: { userId },
    });
  }
  // If neither is provided, this is a no-op (client-only logout)
}

// ─── Forgot Password ────────────────────────────────────────────────────────

const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_TTL_MS = 60 * 60 * 1000; // 1 hour

export async function forgotPassword(
  input: ForgotPasswordInput,
): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { email: input.email },
  });

  // Always return silently to prevent email enumeration
  if (!user?.isActive) return;

  // Apple-only accounts have no password to reset
  if (!user.passwordHash) return;

  // Generate a cryptographically secure reset token
  const resetToken = crypto.randomBytes(RESET_TOKEN_BYTES).toString("hex");
  const expiresAt = new Date(Date.now() + RESET_TOKEN_TTL_MS);

  await prisma.user.update({
    where: { id: user.id },
    data: {
      passwordResetToken: resetToken,
      passwordResetExpiresAt: expiresAt,
    },
  });

  // Send password reset email (graceful no-op if RESEND_API_KEY not configured)
  const { sendPasswordResetEmail } = await import("../../lib/email");
  const resetUrl = `${env.API_BASE_URL}/reset-password?token=${resetToken}`;
  await sendPasswordResetEmail(user.email, resetUrl);
}

// ─── Reset Password ─────────────────────────────────────────────────────────

export async function resetPassword(input: ResetPasswordInput): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { passwordResetToken: input.token },
  });

  if (!user) {
    throw new ValidationError("Invalid or expired reset token");
  }

  if (
    !user.passwordResetExpiresAt ||
    user.passwordResetExpiresAt < new Date()
  ) {
    // Clear the expired token
    await prisma.user.updateMany({
      where: { id: user.id, passwordResetToken: input.token },
      data: {
        passwordResetToken: null,
        passwordResetExpiresAt: null,
      },
    });
    throw new ValidationError("Reset token has expired");
  }

  const passwordHash = await hashPassword(input.new_password);

  // Update password, clear reset token, and invalidate all refresh tokens in a transaction
  await prisma.$transaction(async (tx) => {
    const changed = await tx.user.updateMany({
      where: { id: user.id, isActive: true, passwordResetToken: input.token, passwordResetExpiresAt: { gt: new Date() } },
      data: {
        passwordHash,
        passwordResetToken: null,
        passwordResetExpiresAt: null,
      },
    });

    if (changed.count !== 1) throw new ValidationError("Invalid or expired reset token");

    // Invalidate all active sessions so the user must re-login with the new password
    await tx.refreshToken.deleteMany({
      where: { userId: user.id },
    });
  });
}
