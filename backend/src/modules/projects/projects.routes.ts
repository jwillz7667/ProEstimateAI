import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
} from './projects.controller';
import { validate } from '../../middleware/validate.middleware';
import { createProjectSchema, updateProjectSchema } from './projects.validators';
import assetNestedRoutes from '../assets/assets.nested.routes';
import generationNestedRoutes from '../generations/generations.nested.routes';
import activityNestedRoutes from '../activity/activity.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// CRUD routes
router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.post('/', validate(createProjectSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateProjectSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

// Nested resource routes
router.use('/:projectId/assets', assetNestedRoutes);
router.use('/:projectId/generations', generationNestedRoutes);
router.use('/:projectId/activity', activityNestedRoutes);

export default router;
