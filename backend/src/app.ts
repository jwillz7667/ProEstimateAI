import express from 'express';
import cors from 'cors';
import compression from 'compression';
import pinoHttp from 'pino-http';
import { corsOptions } from './config/cors';
import { logger } from './config/logger';
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
import proposalsShareRoutes from './modules/proposals/proposals-share.routes';
import invoicesRoutes from './modules/invoices/invoices.routes';
import invoiceLineItemsRoutes from './modules/invoice-line-items/invoice-line-items.routes';
import pricingProfilesRoutes from './modules/pricing-profiles/pricing-profiles.routes';
import laborRatesRoutes from './modules/labor-rates/labor-rates.routes';
import activityRoutes from './modules/activity/activity.routes';
import commerceRoutes from './modules/commerce/commerce.routes';
import commerceWebhookRoutes from './modules/commerce/commerce-webhook.routes';
import usageRoutes from './modules/usage/usage.routes';
import dashboardRoutes from './modules/dashboard/dashboard.routes';
import contractorsRoutes from './modules/contractors/contractors.routes';
import materialsPricingRoutes from './modules/materials-pricing/materials-pricing.routes';

export function createApp() {
  const app = express();

  // Railway runs behind a reverse proxy — trust it for correct IP detection
  app.set('trust proxy', 1);

  // Global middleware
  app.use(cors(corsOptions));
  app.use(compression()); // gzip responses — reduces bandwidth 60-80%
  app.use(express.json({ limit: '10mb' }));
  app.use(requestIdMiddleware);
  app.use(globalRateLimit);

  // Structured request logging (production only — dev uses pino-pretty on stdout)
  if (process.env.NODE_ENV === 'production') {
    app.use(pinoHttp({
      logger,
      autoLogging: {
        ignore: (req) => (req.url === '/health'), // Don't log health checks
      },
      customSuccessMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
      customErrorMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
      serializers: {
        req: (req) => ({ method: req.method, url: req.url, id: req.id }),
        res: (res) => ({ statusCode: res.statusCode }),
      },
    }));
  }

  // Health (no auth)
  app.use('/health', healthRoutes);

  // V1 routes
  const v1 = express.Router();
  v1.use('/auth', authRoutes);

  // Public image endpoints (no auth — served to AsyncImage / <img> tags)
  v1.get('/generations/:id/preview', async (req, res, next) => {
    try {
      const { getPublicImageData } = await import('./modules/generations/generations.service');
      const imageResult = await getPublicImageData(req.params.id);
      if (!imageResult) {
        res.status(404).json({ ok: false, error: { code: 'IMAGE_NOT_READY', message: 'Image not available', retryable: true } });
        return;
      }
      res.set('Content-Type', imageResult.mimeType);
      res.set('Cache-Control', 'public, max-age=31536000, immutable');
      res.send(imageResult.data);
    } catch (err) { next(err); }
  });
  v1.get('/assets/:id/image', async (req, res, next) => {
    try {
      const { getPublicAssetImage } = await import('./modules/assets/assets.service');
      const imageResult = await getPublicAssetImage(req.params.id);
      if (!imageResult) {
        res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Image not found' } });
        return;
      }
      res.set('Content-Type', imageResult.mimeType);
      res.set('Cache-Control', 'public, max-age=31536000, immutable');
      res.send(imageResult.data);
    } catch (err) { next(err); }
  });
  v1.get('/companies/:id/logo', async (req, res, next) => {
    try {
      const { getPublicCompanyLogo } = await import('./modules/companies/companies.service');
      const imageResult = await getPublicCompanyLogo(req.params.id);
      if (!imageResult) {
        res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'No logo set for this company' } });
        return;
      }
      res.set('Content-Type', imageResult.mimeType);
      res.set('Cache-Control', 'public, max-age=86400, immutable');
      res.send(imageResult.data);
    } catch (err) { next(err); }
  });

  // Public proposal share page (no auth — accessed by clients via share link)
  v1.use('/proposals/share', proposalsShareRoutes);

  // App Store Server Notifications webhook (no auth — Apple sends JWS-signed payloads)
  v1.use('/commerce/webhooks', commerceWebhookRoutes);

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
  v1.use('/dashboard', requireAuth, dashboardRoutes);
  v1.use('/contractors', requireAuth, contractorsRoutes);
  v1.use('/materials-pricing', requireAuth, materialsPricingRoutes);
  app.use('/v1', v1);

  // Global error handler
  app.use(errorHandler);

  return app;
}
