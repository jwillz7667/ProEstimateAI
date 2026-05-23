import { Router, Request, Response, NextFunction } from "express";
import {
  registerApnsTokenHandler,
  deregisterApnsTokenHandler,
} from "./devices.controller";
import { validate } from "../../middleware/validate.middleware";
import {
  registerApnsTokenSchema,
  deregisterApnsTokenSchema,
} from "./devices.validators";

const router = Router();

function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
  return (req: Request, res: Response, next: NextFunction) =>
    fn(req, res, next).catch(next);
}

router.post(
  "/apns",
  validate(registerApnsTokenSchema),
  asyncHandler(registerApnsTokenHandler),
);

router.delete(
  "/apns",
  validate(deregisterApnsTokenSchema),
  asyncHandler(deregisterApnsTokenHandler),
);

export default router;
