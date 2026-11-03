import { Prisma } from '@prisma/client';
import { prisma } from '../../config/database';

export interface DashboardMoney {
  currency_code: string;
  amount: string;
}

export interface DashboardAttentionTarget {
  document_id: string;
  project_id: string;
  document_number: string;
  project_title: string;
  client_name: string | null;
}

export interface DashboardAttentionGroup {
  kind: 'overdue_invoice' | 'changes_requested' | 'approved_change_order' | 'approved_estimate' | 'unanswered_proposal' | 'draft_estimate';
  count: number;
  amounts: DashboardMoney[];
  target: DashboardAttentionTarget;
}

interface AttentionResult {
  count: number;
  amounts: DashboardMoney[];
  target: DashboardAttentionTarget | null;
}

/** Aggregate the whole eligible set, but return only its oldest next action.
 * Money stays decimal text and separate by currency; Home never adds USD to CAD.
 */
async function summarize(tx: Prisma.TransactionClient, eligible: Prisma.Sql): Promise<AttentionResult> {
  const [result] = await tx.$queryRaw<AttentionResult[]>(Prisma.sql`
    WITH eligible AS (${eligible})
    SELECT
      (SELECT COUNT(*)::integer FROM eligible) AS count,
      (SELECT COALESCE(jsonb_agg(m ORDER BY m.currency_code), '[]'::jsonb)
        FROM (SELECT currency_code, SUM(amount)::text AS amount
              FROM eligible GROUP BY currency_code) m) AS amounts,
      (SELECT row_to_json(t) FROM (
        SELECT document_id, project_id, document_number, project_title, client_name
        FROM eligible ORDER BY action_at ASC, document_id ASC LIMIT 1
      ) t) AS target
  `);
  return result;
}

/** Fresh, tenant-scoped next actions. A consistent read keeps counts and their
 * representative document together while another device sends or pays a quote.
 * A proposal becomes a follow-up after three days, not immediately after send.
 */
export async function getAttention(companyId: string, now = new Date()) {
  const followUpBefore = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000);
  // Prisma DateTime columns are UTC timestamp-without-time-zone. Bind ISO text
  // explicitly as timestamp so the database session's time zone cannot move
  // the three-day or due-date boundary when comparing a JS Date parameter.
  const nowUTC = now.toISOString();
  const followUpBeforeUTC = followUpBefore.toISOString();
  return prisma.$transaction(async tx => {
    const overdue = await summarize(tx, Prisma.sql`
      SELECT i.id AS document_id, i."projectId" AS project_id,
        i."invoiceNumber" AS document_number, p.title AS project_title,
        c.name AS client_name, i."amountDue" AS amount,
        COALESCE(NULLIF(UPPER(i."currencyCode"), ''), 'USD') AS currency_code,
        i."dueDate" AS action_at
      FROM "Invoice" i JOIN "Project" p ON p.id = i."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = i."clientId" AND c."companyId" = ${companyId}
      WHERE i."companyId" = ${companyId}
        AND i.status IN ('SENT', 'VIEWED', 'OVERDUE', 'PARTIALLY_PAID')
        AND i."amountDue" > 0 AND i."dueDate" < ${nowUTC}::timestamp
    `);
    const requestedChanges = await summarize(tx, Prisma.sql`
      SELECT q.id AS document_id, q."projectId" AS project_id,
        COALESCE(q."proposalNumber", e."estimateNumber") AS document_number,
        p.title AS project_title, c.name AS client_name,
        e."totalAmount" AS amount, 'USD'::text AS currency_code,
        q."changesRequestedAt" AS action_at
      FROM "Proposal" q
      JOIN "Estimate" e ON e.id = q."estimateId" AND e."companyId" = ${companyId}
      JOIN "Project" p ON p.id = q."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = p."clientId" AND c."companyId" = ${companyId}
      WHERE q."companyId" = ${companyId} AND q.status IN ('SENT', 'VIEWED')
        AND e.status IN ('DRAFT', 'SENT') AND q."respondedAt" IS NULL
        AND q."changesRequestedAt" IS NOT NULL AND p.status <> 'ARCHIVED'
    `);
    const approvedChanges = await summarize(tx, Prisma.sql`
      SELECT o.id AS document_id, o."projectId" AS project_id,
        COALESCE(q."proposalNumber", e."estimateNumber") AS document_number,
        p.title AS project_title, c.name AS client_name,
        0::decimal AS amount, 'USD'::text AS currency_code, o."createdAt" AS action_at
      FROM "ChangeOrder" o
      JOIN "Estimate" e ON e.id = o."estimateId" AND e."companyId" = ${companyId}
      JOIN "Proposal" q ON q.id = o."proposalId" AND q."companyId" = ${companyId}
      JOIN "Project" p ON p.id = o."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = p."clientId" AND c."companyId" = ${companyId}
      WHERE o."companyId" = ${companyId} AND o.status = 'APPROVED'
        AND e.status = 'APPROVED' AND q.status = 'APPROVED' AND p.status <> 'ARCHIVED'
        AND NOT EXISTS (SELECT 1 FROM "ChangeOrder" newer WHERE newer."companyId" = ${companyId}
          AND newer."rootEstimateId" = o."rootEstimateId" AND newer.status IN ('APPROVED', 'APPLIED', 'INCLUDED')
          AND (newer."createdAt", newer.id) > (o."createdAt", o.id))
        AND (o."rootInvoiceId" IS NOT NULL OR NOT EXISTS (SELECT 1 FROM "ChangeOrder" pending
          WHERE pending."companyId" = ${companyId} AND pending."rootEstimateId" = o."rootEstimateId" AND pending.status IN ('DRAFT', 'SENT')))
    `);
    const approved = await summarize(tx, Prisma.sql`
      SELECT e.id AS document_id, e."projectId" AS project_id,
        e."estimateNumber" AS document_number, p.title AS project_title,
        c.name AS client_name, e."totalAmount" AS amount, 'USD'::text AS currency_code,
        e."updatedAt" AS action_at
      FROM "Estimate" e JOIN "Project" p ON p.id = e."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = p."clientId" AND c."companyId" = ${companyId}
      WHERE e."companyId" = ${companyId} AND e.status = 'APPROVED'
        AND p.status <> 'ARCHIVED'
        AND NOT EXISTS (SELECT 1 FROM "ChangeOrder" o WHERE o."estimateId" = e.id AND o."companyId" = ${companyId})
        AND NOT EXISTS (SELECT 1 FROM "ChangeOrder" o WHERE o."baseEstimateId" = e.id AND o."companyId" = ${companyId}
          AND o.status IN ('DRAFT', 'SENT', 'APPROVED', 'APPLIED', 'INCLUDED', 'CHANGES_REQUESTED'))
        AND NOT EXISTS (SELECT 1 FROM "Invoice" i WHERE i."estimateId" = e.id
          AND i."companyId" = ${companyId} AND i.status <> 'VOID')
    `);
    const unanswered = await summarize(tx, Prisma.sql`
      SELECT q.id AS document_id, q."projectId" AS project_id,
        COALESCE(q."proposalNumber", e."estimateNumber") AS document_number,
        p.title AS project_title, c.name AS client_name,
        e."totalAmount" AS amount, 'USD'::text AS currency_code,
        q."sentAt" AS action_at
      FROM "Proposal" q
      JOIN "Estimate" e ON e.id = q."estimateId" AND e."companyId" = ${companyId}
      JOIN "Project" p ON p.id = q."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = p."clientId" AND c."companyId" = ${companyId}
      WHERE q."companyId" = ${companyId} AND q.status IN ('SENT', 'VIEWED')
        AND e.status IN ('DRAFT', 'SENT')
        AND q."respondedAt" IS NULL AND q."sentAt" <= ${followUpBeforeUTC}::timestamp
        AND q."changesRequestedAt" IS NULL
        AND (q."expiresAt" IS NULL OR q."expiresAt" > ${nowUTC}::timestamp)
        AND p.status <> 'ARCHIVED'
    `);
    const drafts = await summarize(tx, Prisma.sql`
      SELECT e.id AS document_id, e."projectId" AS project_id,
        e."estimateNumber" AS document_number, p.title AS project_title,
        c.name AS client_name, e."totalAmount" AS amount, 'USD'::text AS currency_code,
        e."updatedAt" AS action_at
      FROM "Estimate" e JOIN "Project" p ON p.id = e."projectId" AND p."companyId" = ${companyId}
      LEFT JOIN "Client" c ON c.id = p."clientId" AND c."companyId" = ${companyId}
      WHERE e."companyId" = ${companyId} AND e.status = 'DRAFT'
        AND p.status NOT IN ('ARCHIVED', 'COMPLETED')
        AND NOT EXISTS (SELECT 1 FROM "Proposal" q WHERE q."estimateId" = e.id
          AND q."companyId" = ${companyId} AND q.status <> 'DRAFT')
    `);
    const kinds = ['overdue_invoice', 'changes_requested', 'approved_change_order', 'approved_estimate', 'unanswered_proposal', 'draft_estimate'] as const;
    const groups: DashboardAttentionGroup[] = [];
    for (const [index, result] of [overdue, requestedChanges, approvedChanges, approved, unanswered, drafts].entries()) {
      // Changes may create either an extra invoice or a credit. Never present
      // their full revised contract value (or an offsetting net) as revenue.
      if (result.count > 0 && result.target) groups.push({ kind: kinds[index], ...result, amounts: kinds[index] === 'approved_change_order' ? [] : result.amounts, target: result.target });
    }
    return { generated_at: now.toISOString(), follow_up_after_days: 3, groups };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
}
