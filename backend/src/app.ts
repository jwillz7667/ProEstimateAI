import express from 'express';
import cors from 'cors';
import { corsOptions } from './config/cors';
import { requestIdMiddleware } from './middleware/request-id.middleware';
import { globalRateLimit } from './middleware/rate-limit.middleware';
import { errorHandler } from './middleware/error-handler.middleware';
import { requireAuth } from './middleware/auth.middleware';

// Route imports
import healthRoutes from './modules/health/health.routes';
import authRoutes from './modules/auth/auth.routes';
import usersRoutes from './modules/users/users.routes';
import companiesRoutes from './modules/companies/companies.routes';
import clientsRoutes from './modules/clients/clients.routes';
import projectsRoutes from './modules/projects/projects.routes';
import assetsRoutes from './modules/assets/assets.routes';
import generationsRoutes from './modules/generations/generations.routes';
import materialsRoutes from './modules/materials/materials.routes';
import estimatesRoutes from './modules/estimates/estimates.routes';
import estimateLineItemsRoutes from './modules/estimate-line-items/estimate-line-items.routes';
import proposalsRoutes from './modules/proposals/proposals.routes';
import invoicesRoutes from './modules/invoices/invoices.routes';
import invoiceLineItemsRoutes from './modules/invoice-line-items/invoice-line-items.routes';
import pricingProfilesRoutes from './modules/pricing-profiles/pricing-profiles.routes';
import laborRatesRoutes from './modules/labor-rates/labor-rates.routes';
import activityRoutes from './modules/activity/activity.routes';
import commerceRoutes from './modules/commerce/commerce.routes';
import usageRoutes from './modules/usage/usage.routes';

export function createApp() {
  const app = express();

  // Global middleware
  app.use(cors(corsOptions));
  app.use(express.json({ limit: '10mb' }));
  app.use(requestIdMiddleware);
  app.use(globalRateLimit);

  // Health (no auth)
  app.use('/health', healthRoutes);

  // V1 routes
  const v1 = express.Router();
  v1.use('/auth', authRoutes);
  v1.use('/users', requireAuth, usersRoutes);
  v1.use('/companies', requireAuth, companiesRoutes);
  v1.use('/clients', requireAuth, clientsRoutes);
  v1.use('/projects', requireAuth, projectsRoutes);
  v1.use('/assets', requireAuth, assetsRoutes);
  v1.use('/generations', requireAuth, generationsRoutes);
  v1.use('/materials', requireAuth, materialsRoutes);
  v1.use('/estimates', requireAuth, estimatesRoutes);
  v1.use('/estimate-line-items', requireAuth, estimateLineItemsRoutes);
  v1.use('/proposals', requireAuth, proposalsRoutes);
  v1.use('/invoices', requireAuth, invoicesRoutes);
  v1.use('/invoice-line-items', requireAuth, invoiceLineItemsRoutes);
  v1.use('/pricing-profiles', requireAuth, pricingProfilesRoutes);
  v1.use('/labor-rates', requireAuth, laborRatesRoutes);
  v1.use('/activity', requireAuth, activityRoutes);
  v1.use('/commerce', requireAuth, commerceRoutes);
  v1.use('/usage', requireAuth, usageRoutes);
  app.use('/v1', v1);

  // Global error handler
  app.use(errorHandler);

  return app;
}
