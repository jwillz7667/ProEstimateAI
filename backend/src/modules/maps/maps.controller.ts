import { Request, Response } from "express";
import { sendSuccess } from "../../lib/envelope";
import { NotFoundError } from "../../lib/errors";
import * as mapsService from "./maps.service";
import { GoogleMapsConfigError, GoogleMapsRequestError } from "./maps.service";
import { toGeocodeDto, toRoofScoutingDto, LawnAreaDto } from "./maps.dto";

/**
 * `feature is not configured` is a configuration error, not a request
 * error — surface a 503 so the iOS client can disable the maps UI
 * gracefully instead of treating it as a 5xx outage.
 */
function handleConfigError(res: Response): void {
  res.status(503).json({
    ok: false,
    error: {
      code: "MAPS_NOT_CONFIGURED",
      message: "Property maps integration is not configured on this server",
    },
  });
}

function handleUpstreamError(res: Response, err: GoogleMapsRequestError): void {
  res.status(502).json({
    ok: false,
    error: {
      code: "MAPS_UPSTREAM_ERROR",
      message: err.message,
    },
  });
}

export async function geocodeHandler(req: Request, res: Response) {
  try {
    const result = await mapsService.geocode(req.body);
    if (!result) {
      throw new NotFoundError("Address", req.body.address);
    }
    sendSuccess(res, toGeocodeDto(result));
  } catch (err) {
    if (err instanceof GoogleMapsConfigError) {
      handleConfigError(res);
      return;
    }
    if (err instanceof GoogleMapsRequestError) {
      handleUpstreamError(res, err);
      return;
    }
    throw err;
  }
}

export async function lawnAreaHandler(req: Request, res: Response) {
  try {
    const result = await mapsService.measureLawn(req.body, req.companyId!);
    const dto: LawnAreaDto = {
      area_sq_meters: result.areaSqMeters,
      area_sq_ft: result.areaSqFt,
      centroid_latitude: result.centroidLatitude,
      centroid_longitude: result.centroidLongitude,
    };
    sendSuccess(res, dto);
  } catch (err) {
    if (err instanceof GoogleMapsConfigError) {
      handleConfigError(res);
      return;
    }
    throw err;
  }
}

export async function roofScoutingHandler(req: Request, res: Response) {
  try {
    const result = await mapsService.scoutRoof(req.body, req.companyId!);
    if (!result) {
      throw new NotFoundError(
        "Roof building data",
        req.body.address ?? `${req.body.latitude},${req.body.longitude}`,
      );
    }
    sendSuccess(res, {
      ...toRoofScoutingDto(result.result),
      resolved_address: result.resolvedAddress,
    });
  } catch (err) {
    if (err instanceof GoogleMapsConfigError) {
      handleConfigError(res);
      return;
    }
    if (err instanceof GoogleMapsRequestError) {
      handleUpstreamError(res, err);
      return;
    }
    throw err;
  }
}

/**
 * Public-ish endpoint: serves a satellite preview as binary PNG so the
 * iOS client never sees the GOOGLE_MAPS_API_KEY. Auth is required (it's
 * still under `/v1`) so this can't be hot-linked from anywhere outside
 * the contractor's session.
 */
export async function staticMapHandler(req: Request, res: Response) {
  try {
    // The validate() middleware already coerced query params, but Express
    // hands them back as the raw shape — re-cast explicitly.
    const query =
      req.query as unknown as import("./maps.validators").StaticMapQuery;
    const { data, mimeType } = await mapsService.staticMap(query);
    res.set("Content-Type", mimeType);
    res.set("Cache-Control", "private, max-age=600");
    res.send(data);
  } catch (err) {
    if (err instanceof GoogleMapsConfigError) {
      handleConfigError(res);
      return;
    }
    if (err instanceof GoogleMapsRequestError) {
      handleUpstreamError(res, err);
      return;
    }
    throw err;
  }
}
