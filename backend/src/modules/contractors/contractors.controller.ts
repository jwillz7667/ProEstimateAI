import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import * as contractorsService from './contractors.service';

/**
 * GET /v1/contractors/search?project_type=KITCHEN&lat=33.749&lng=-84.388&radius=25
 */
export async function searchHandler(req: Request, res: Response) {
  const projectType = (req.query.project_type as string) || 'CUSTOM';
  const lat = parseFloat(req.query.lat as string);
  const lng = parseFloat(req.query.lng as string);
  const radius = parseFloat(req.query.radius as string) || 25;

  if (isNaN(lat) || isNaN(lng)) {
    res.status(400).json({
      ok: false,
      error: { code: 'INVALID_LOCATION', message: 'lat and lng query parameters are required' },
    });
    return;
  }

  const results = await contractorsService.searchContractors(projectType, lat, lng, radius);
  sendSuccess(res, results);
}
