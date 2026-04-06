import { Router } from 'express';
import { validate } from '../../middleware/validate.middleware';
import { authRateLimit } from '../../middleware/rate-limit.middleware';
import {
  signupSchema,
  loginSchema,
  appleSignInSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
} from './auth.validators';
import {
  signupHandler,
  loginHandler,
  appleSignInHandler,
  refreshHandler,
  logoutHandler,
  forgotPasswordHandler,
  resetPasswordHandler,
} from './auth.controller';

const router = Router();

// All auth routes are rate-limited to 10 requests/minute per IP
router.use(authRateLimit);

// POST /v1/auth/signup
router.post('/signup', validate(signupSchema), signupHandler);

// POST /v1/auth/login
router.post('/login', validate(loginSchema), loginHandler);

// POST /v1/auth/apple-signin
router.post('/apple-signin', validate(appleSignInSchema), appleSignInHandler);

// POST /v1/auth/refresh
router.post('/refresh', validate(refreshSchema), refreshHandler);

// POST /v1/auth/logout
// Logout accepts an optional refresh_token. The user may or may not be
// authenticated (Bearer header is not required for logout).
router.post('/logout', validate(logoutSchema), logoutHandler);

// POST /v1/auth/forgot-password
router.post('/forgot-password', validate(forgotPasswordSchema), forgotPasswordHandler);

// POST /v1/auth/reset-password
router.post('/reset-password', validate(resetPasswordSchema), resetPasswordHandler);

export default router;
