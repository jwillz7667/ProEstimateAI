import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as materialsService from './materials.service';
import { toMaterialDto } from './materials.dto';

/**
 * GET /v1/generations/:generationId/materials
 * List all material suggestions for a generation.
 */
export async function listByGenerationHandler(req: Request, res: Response) {
  const materials = await materialsService.listByGeneration(
    param(req.params.generationId),
    req.companyId!
  );
  sendSuccess(res, materials.map(toMaterialDto));
}

/**
 * PATCH /v1/materials/:id
 * Update material selection (toggle is_selected).
 */
export async function updateHandler(req: Request, res: Response) {
  const material = await materialsService.updateSelection(
    param(req.params.id),
    req.companyId!,
    req.body.is_selected
  );
  sendSuccess(res, toMaterialDto(material));
}
