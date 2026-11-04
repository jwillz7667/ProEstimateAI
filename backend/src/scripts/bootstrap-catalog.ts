import 'dotenv/config';
import { prisma } from '../config/database';
import { logger } from '../config/logger';
import { bootstrapCatalog } from '../lib/catalog-bootstrap';

async function main(): Promise<void> {
  try {
    await bootstrapCatalog(prisma);
    logger.info('Commerce catalog ready; existing plans and products preserved');
  } finally {
    await prisma.$disconnect();
  }
}

void main().catch((err: unknown) => {
  logger.error({ err }, 'Commerce catalog bootstrap failed');
  process.exitCode = 1;
});
