declare namespace Express {
  interface Request {
    userId?: string;
    companyId?: string;
    requestId?: string;
  }
}
