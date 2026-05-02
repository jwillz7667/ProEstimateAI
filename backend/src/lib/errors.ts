export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public fieldErrors?: Record<string, string[]>,
    public retryable: boolean = false,
    public paywall?: any
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string, id?: string) {
    super(404, 'NOT_FOUND', id ? `${resource} with id '${id}' not found` : `${resource} not found`);
    this.name = 'NotFoundError';
  }
}

export class ValidationError extends AppError {
  constructor(message: string, fieldErrors?: Record<string, string[]>) {
    super(400, 'VALIDATION_ERROR', message, fieldErrors);
    this.name = 'ValidationError';
  }
}

export class AuthenticationError extends AppError {
  constructor(message: string = 'Authentication required') {
    super(401, 'UNAUTHORIZED', message);
    this.name = 'AuthenticationError';
  }
}

export class AuthorizationError extends AppError {
  constructor(message: string = 'Insufficient permissions') {
    super(403, 'FORBIDDEN', message);
    this.name = 'AuthorizationError';
  }
}

export class PaywallError extends AppError {
  constructor(message: string, paywallDecision: any) {
    super(402, 'PAYWALL_REQUIRED', message, undefined, false, paywallDecision);
    this.name = 'PaywallError';
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(409, 'CONFLICT', message);
    this.name = 'ConflictError';
  }
}

/**
 * Thrown when a StoreKit transaction's bound `appAccountToken` doesn't
 * resolve to the authenticated user. This happens when the device's
 * App Store Apple ID differs from the ProEstimate account that initiated
 * the purchase — e.g. a contractor signed into the app with one account
 * but tries to upgrade while signed into a different iCloud / App Store
 * Apple ID. The 403 + dedicated `ACCOUNT_MISMATCH` code lets iOS render
 * a specific recovery prompt instead of a generic "validation failed".
 */
export class AccountMismatchError extends AppError {
  constructor(message: string = 'This purchase is associated with a different Apple ID than your ProEstimate account.') {
    super(403, 'ACCOUNT_MISMATCH', message);
    this.name = 'AccountMismatchError';
  }
}
