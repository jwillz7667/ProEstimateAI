import { prisma } from '../../config/database';
import { hashPassword, verifyPassword } from '../../lib/hash';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
  type JwtPayload,
} from '../../lib/jwt';
import { generateId } from '../../lib/id';
import { AuthenticationError, ConflictError } from '../../lib/errors';
import type { User, Company } from '@prisma/client';
import type { SignupInput, LoginInput } from './auth.validators';

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
    throw new ConflictError('A user with this email already exists');
  }

  // 2. Hash password
  const passwordHash = await hashPassword(input.password);

  // 3. Look up the FREE_STARTER plan (must exist from seed)
  const freePlan = await prisma.plan.findUniqueOrThrow({
    where: { code: 'FREE_STARTER' },
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
        role: 'OWNER',
      },
    });

    // Create FREE entitlement
    await tx.userEntitlement.create({
      data: {
        userId: createdUser.id,
        companyId: createdCompany.id,
        planId: freePlan.id,
        status: 'FREE',
      },
    });

    // Initialize usage buckets: 3 AI generations, 3 quote exports
    await tx.usageBucket.createMany({
      data: [
        {
          userId: createdUser.id,
          companyId: createdCompany.id,
          metricCode: 'AI_GENERATION',
          includedQuantity: 3,
          consumedQuantity: 0,
          resetPolicy: 'NEVER',
          source: 'STARTER_CREDITS',
        },
        {
          userId: createdUser.id,
          companyId: createdCompany.id,
          metricCode: 'QUOTE_EXPORT',
          includedQuantity: 3,
          consumedQuantity: 0,
          resetPolicy: 'NEVER',
          source: 'STARTER_CREDITS',
        },
      ],
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
    throw new AuthenticationError('Invalid email or password');
  }

  // 2. Verify password
  const passwordValid = await verifyPassword(input.password, user.passwordHash);
  if (!passwordValid) {
    throw new AuthenticationError('Invalid email or password');
  }

  // 3. Check account is active
  if (!user.isActive) {
    throw new AuthenticationError('Account is deactivated');
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

// ─── Refresh ─────────────────────────────────────────────────────────────────

export async function refresh(refreshTokenValue: string): Promise<TokenPairResult> {
  // 1. Verify the JWT signature and expiry
  let payload: JwtPayload;
  try {
    payload = verifyRefreshToken(refreshTokenValue);
  } catch {
    throw new AuthenticationError('Invalid or expired refresh token');
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
    throw new AuthenticationError('Refresh token has been revoked');
  }

  if (storedToken.expiresAt < new Date()) {
    // Clean up expired token
    await prisma.refreshToken.delete({ where: { id: storedToken.id } });
    throw new AuthenticationError('Refresh token has expired');
  }

  // 3. Rotate: delete old token, issue new pair
  await prisma.refreshToken.delete({ where: { id: storedToken.id } });

  const jwtPayload: JwtPayload = {
    userId: payload.userId,
    companyId: payload.companyId,
  };
  const newAccessToken = signAccessToken(jwtPayload);
  const newRefreshToken = signRefreshToken(jwtPayload);

  // 4. Store the new refresh token
  await prisma.refreshToken.create({
    data: {
      userId: payload.userId,
      token: newRefreshToken,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });

  return { accessToken: newAccessToken, refreshToken: newRefreshToken };
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
