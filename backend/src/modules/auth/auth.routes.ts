import { Router } from "express";
import { validate } from "../../middleware/validate.middleware";
import { authRateLimit } from "../../middleware/rate-limit.middleware";
import {
  signupSchema,
  loginSchema,
  appleSignInSchema,
  googleSignInSchema,
  refreshSchema,
  logoutSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
} from "./auth.validators";
import {
  signupHandler,
  loginHandler,
  appleSignInHandler,
  googleSignInHandler,
  refreshHandler,
  logoutHandler,
  forgotPasswordHandler,
  resetPasswordHandler,
} from "./auth.controller";

const router = Router();

// Brute-force-sensitive routes get strict rate limiting
router.post("/signup", authRateLimit, validate(signupSchema), signupHandler);
router.post("/login", authRateLimit, validate(loginSchema), loginHandler);
router.post(
  "/apple-signin",
  authRateLimit,
  validate(appleSignInSchema),
  appleSignInHandler,
);
router.post(
  "/google-signin",
  authRateLimit,
  validate(googleSignInSchema),
  googleSignInHandler,
);
router.post(
  "/forgot-password",
  authRateLimit,
  validate(forgotPasswordSchema),
  forgotPasswordHandler,
);
router.post(
  "/reset-password",
  authRateLimit,
  validate(resetPasswordSchema),
  resetPasswordHandler,
);

// Refresh, logout use global rate limit only (not brute-force targets)
router.post("/refresh", validate(refreshSchema), refreshHandler);
router.post("/logout", validate(logoutSchema), logoutHandler);

export default router;
