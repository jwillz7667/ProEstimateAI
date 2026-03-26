import 'dotenv/config';
import { createApp } from './app';
import { prisma } from './config/database';
import { env } from './config/env';
import { logger } from './config/logger';

async function main() {
  try {
    await prisma.$connect();
    logger.info('Database connected');

    const app = createApp();

    app.listen(env.PORT, () => {
      logger.info(`Server running on port ${env.PORT} [${env.NODE_ENV}]`);
    });
  } catch (err) {
    logger.fatal(err, 'Failed to start server');
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down');
  await prisma.$disconnect();
  process.exit(0);
});

main();
