import { Router, Request, Response, NextFunction } from "express";
import {
  geocodeHandler,
  lawnAreaHandler,
  roofScoutingHandler,
  staticMapHandler,
} from "./maps.controller";
import { validate } from "../../middleware/validate.middleware";
import {
  geocodeSchema,
  lawnAreaSchema,
  roofScoutingSchema,
  staticMapQuerySchema,
} from "./maps.validators";

const router = Router();

function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
  return (req: Request, res: Response, next: NextFunction) =>
    fn(req, res, next).catch(next);
}

// POST /v1/maps/geocode               — address → lat/lng
router.post("/geocode", validate(geocodeSchema), asyncHandler(geocodeHandler));

// POST /v1/maps/lawn-area             — polygon → sq ft (also persists when project_id passed)
router.post(
  "/lawn-area",
  validate(lawnAreaSchema),
  asyncHandler(lawnAreaHandler),
);

// POST /v1/maps/roof-scouting         — address or lat/lng → Solar API roof report
router.post(
  "/roof-scouting",
  validate(roofScoutingSchema),
  asyncHandler(roofScoutingHandler),
);

// GET /v1/maps/static-image           — proxied satellite tile, keeps API key server-side
router.get(
  "/static-image",
  validate(staticMapQuerySchema, "query"),
  asyncHandler(staticMapHandler),
);

export default router;
