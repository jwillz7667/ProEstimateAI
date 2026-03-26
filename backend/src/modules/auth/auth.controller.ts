import { Request, Response, NextFunction } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { toUserDto, toCompanyDto } from './auth.dto';
import type { AuthResponseDto, TokenPairDto } from './auth.dto';
import type { SignupInput, LoginInput, AppleSignInInput, RefreshInput, LogoutInput } from './auth.validators';
import * as authService from './auth.service';

// ─── Async handler ───────────────────────────────────────────────────────────
// Wraps async route handlers so rejected promises are forwarded to Express
// error-handling middleware via next(), eliminating the need for try/catch
// in every controller method.

function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
  return (req: Request, res: Response, next: NextFunction) =>
    fn(req, res, next).catch(next);
}

// ─── POST /v1/auth/signup ────────────────────────────────────────────────────

export const signupHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const input = req.body as SignupInput;

    const result = await authService.signup(input);

    const data: AuthResponseDto = {
      user: toUserDto(result.user),
      company: toCompanyDto(result.company),
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
    };

    sendSuccess(res, data, { statusCode: 201 });
  },
);

// ─── POST /v1/auth/login ────────────────────────────────────────────────────

export const loginHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const input = req.body as LoginInput;

    const result = await authService.login(input);

    const data: AuthResponseDto = {
      user: toUserDto(result.user),
      company: toCompanyDto(result.company),
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
    };

    sendSuccess(res, data);
  },
);

// ─── POST /v1/auth/apple-signin ─────────────────────────────────────────────

export const appleSignInHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const input = req.body as AppleSignInInput;

    const result = await authService.appleSignIn(input);

    const data: AuthResponseDto = {
      user: toUserDto(result.user),
      company: toCompanyDto(result.company),
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
    };

    sendSuccess(res, data);
  },
);

// ─── POST /v1/auth/refresh ──────────────────────────────────────────────────

export const refreshHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const { refresh_token } = req.body as RefreshInput;

    const result = await authService.refresh(refresh_token);

    const data: TokenPairDto = {
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
    };

    sendSuccess(res, data);
  },
);

// ─── POST /v1/auth/logout ───────────────────────────────────────────────────

export const logoutHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const body = req.body as LogoutInput;

    // userId may be undefined if no Bearer token was sent (unauthenticated logout)
    await authService.logout(req.userId, body.refresh_token);

    sendSuccess(res, {});
  },
);
