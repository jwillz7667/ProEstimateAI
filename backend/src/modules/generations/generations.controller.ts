import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as generationsService from './generations.service';
import { toGenerationDto } from './generations.dto';

/**
 * GET /projects/:projectId/generations
 * List all generations for a project.
 */
export async function listByProjectHandler(req: Request, res: Response) {
  const generations = await generationsService.listByProject(
    param(req.params.projectId),
    req.companyId!
  );
  sendSuccess(res, generations.map(toGenerationDto));
}

/**
 * POST /projects/:projectId/generations
 * Create a new AI generation for a project (with entitlement check).
 */
export async function createHandler(req: Request, res: Response) {
  const generation = await generationsService.create(
    param(req.params.projectId),
    req.companyId!,
    req.userId!,
    req.body
  );
  sendSuccess(res, toGenerationDto(generation), { statusCode: 201 });
}

/**
 * GET /v1/generations/:id
 * Get a single generation by ID.
 */
export async function getByIdHandler(req: Request, res: Response) {
  const generation = await generationsService.getById(param(req.params.id), req.companyId!);
  sendSuccess(res, toGenerationDto(generation));
}
