import { prisma } from '../../config/database';

export interface DashboardSummary {
  active_projects_count: number;
  pending_estimates_count: number;
  revenue_this_month: number;
  invoices_due_count: number;
  generations_remaining: number;
  quotes_remaining: number;
}

export async function getSummary(
  companyId: string,
  userId: string,
): Promise<DashboardSummary> {
  // Start of current month
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

  const [
    activeProjectsCount,
    pendingEstimatesCount,
    revenueResult,
    invoicesDueCount,
    generationBucket,
    quoteBucket,
  ] = await Promise.all([
    // Active projects: status NOT IN (COMPLETED, ARCHIVED)
    prisma.project.count({
      where: {
        companyId,
        status: { notIn: ['COMPLETED', 'ARCHIVED'] },
      },
    }),

    // Pending estimates: status = DRAFT
    prisma.estimate.count({
      where: {
        companyId,
        status: 'DRAFT',
      },
    }),

    // Revenue this month: SUM of paid invoice amounts where paidAt >= month start
    prisma.invoice.aggregate({
      where: {
        companyId,
        status: 'PAID',
        paidAt: { gte: monthStart },
      },
      _sum: { totalAmount: true },
    }),

    // Invoices due: status IN (SENT, VIEWED, OVERDUE, PARTIALLY_PAID)
    prisma.invoice.count({
      where: {
        companyId,
        status: { in: ['SENT', 'VIEWED', 'OVERDUE', 'PARTIALLY_PAID'] },
      },
    }),

    // AI generation credits remaining (sum across all buckets for this metric)
    prisma.usageBucket.findMany({
      where: { userId, metricCode: 'AI_GENERATION' },
    }),

    // Quote export credits remaining (sum across all buckets for this metric)
    prisma.usageBucket.findMany({
      where: { userId, metricCode: 'QUOTE_EXPORT' },
    }),
  ]);

  const revenueThisMonth = revenueResult._sum.totalAmount
    ? Number(revenueResult._sum.totalAmount)
    : 0;

  const generationsRemaining = generationBucket.reduce(
    (sum, b) => sum + Math.max(0, b.includedQuantity - b.consumedQuantity), 0,
  );

  const quotesRemaining = quoteBucket.reduce(
    (sum, b) => sum + Math.max(0, b.includedQuantity - b.consumedQuantity), 0,
  );

  return {
    active_projects_count: activeProjectsCount,
    pending_estimates_count: pendingEstimatesCount,
    revenue_this_month: revenueThisMonth,
    invoices_due_count: invoicesDueCount,
    generations_remaining: generationsRemaining,
    quotes_remaining: quotesRemaining,
  };
}
