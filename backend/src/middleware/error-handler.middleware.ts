import { Request, Response, NextFunction } from 'express';
import { AppError } from '../lib/errors';
import { sendError } from '../lib/envelope';
import { logger } from '../config/logger';

export function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    sendError(res, err.statusCode, {
      code: err.code,
      message: err.message,
      field_errors: err.fieldErrors,
      retryable: err.retryable,
      paywall: err.paywall,
    });
    return;
  }

  logger.error({ err, requestId: req.requestId }, 'Unhandled error');

  sendError(res, 500, {
    code: 'INTERNAL_ERROR',
    message: 'An unexpected error occurred',
    retryable: true,
  });
}
