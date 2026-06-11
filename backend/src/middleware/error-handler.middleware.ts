import { Request, Response, NextFunction } from 'express';
import { AppError } from '../lib/errors';
import { sendError } from '../lib/envelope';
import { logger } from '../config/logger';

// Errors that mean "the client hung up", not "the server faulted". The
// dominant source in production is body-parser throwing while reading a
// request body the client abandoned mid-flight — an iOS app backgrounded
// during a base64 image upload, or a URLSession poll the app cancelled.
// body-parser tags these `{ type: 'request.aborted', code: 'ECONNABORTED' }`;
// raw socket teardown surfaces as ECONNRESET/EPIPE. None are server bugs,
// so they must not pollute the error log or trip alerting.
const CLIENT_DISCONNECT_CODES = new Set(['ECONNABORTED', 'ECONNRESET', 'EPIPE']);

// Classify strictly from the error object. We must NOT consult `req.destroyed`
// here: since Node 14 Readable streams default to `autoDestroy: true`, so a
// request whose body was fully consumed by `express.json()` has
// `req.destroyed === true` by the time any downstream handler throws — true of
// essentially every successful POST. Treating that as a disconnect would drop
// legitimate error responses (e.g. a 409 ConflictError), leaving the client
// hung until its own headers timeout. body-parser/raw-body tag a genuine abort
// `{ type: 'request.aborted', code: 'ECONNABORTED' }`; socket teardown surfaces
// as ECONNRESET/EPIPE. Those are the only trustworthy signals.
function isClientDisconnect(err: Error): boolean {
  const e = err as NodeJS.ErrnoException & { type?: string };
  return (
    e.type === 'request.aborted' ||
    (typeof e.code === 'string' && CLIENT_DISCONNECT_CODES.has(e.code))
  );
}

// The connection is gone or the response already flushed — any further
// write throws ERR_STREAM_WRITE_AFTER_END / ERR_HTTP_HEADERS_SENT, which
// would itself surface as a second "Unhandled error".
function canStillRespond(res: Response): boolean {
  return !res.headersSent && !res.writableEnded;
}

export function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  // Client hung up — log quietly (debug) and never touch the socket.
  if (isClientDisconnect(err)) {
    logger.debug(
      {
        requestId: req.requestId,
        path: req.path,
        code: (err as NodeJS.ErrnoException).code,
      },
      'Request aborted by client',
    );
    return;
  }

  if (err instanceof AppError) {
    if (!canStillRespond(res)) {
      logger.warn(
        { code: err.code, requestId: req.requestId },
        'AppError raised after response was sent — dropping',
      );
      return;
    }
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

  if (!canStillRespond(res)) {
    // Headers already flushed mid-stream (e.g. binary image route) — we
    // can't prepend an error envelope, so just sever the connection.
    res.destroy();
    return;
  }

  sendError(res, 500, {
    code: 'INTERNAL_ERROR',
    message: 'An unexpected error occurred',
    retryable: true,
  });
}
