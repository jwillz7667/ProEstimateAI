import { prisma } from '../../config/database';
import { NotFoundError, PaywallError } from '../../lib/errors';
import { getEffectiveEntitlement } from '../commerce/commerce.service';
import { CreateEstimateExportInput } from './estimate-exports.validators';

/**
 * Verifies that an estimate exists and belongs to the given company.
 * Returns the estimate (with projectId for denormalization on insert).
 */
async function verifyEstimateOwnership(estimateId: string, companyId: string) {
  const estimate = await prisma.estimate.findFirst({
    where: { id: estimateId, companyId },
    select: { id: true, projectId: true, companyId: true },
  });

  if (!estimate) {
    throw new NotFoundError('Estimate', estimateId);
  }

  return estimate;
}

/**
 * Persist a rendered estimate PDF as base64 in `pdfData`. Returns the new
 * record with `pdfData` excluded — the iOS client doesn't need the
 * payload until it downloads the binary, and we don't want it bouncing
 * through every list response.
 */
export async function create(
  estimateId: string,
  companyId: string,
  input: CreateEstimateExportInput,
  userId: string,
) {
  const estimate = await verifyEstimateOwnership(estimateId, companyId);
  const entitlement = await getEffectiveEntitlement(userId, companyId);
  if (!entitlement.feature_flags.CAN_EXPORT_QUOTE) {
    throw new PaywallError('Saving a new PDF quote requires an active subscription', {
      placement: 'QUOTE_LIMIT_HIT', blocking: true,
      trigger_reason: 'Saving a new PDF quote requires an active subscription',
      headline: 'PDF Export Requires Pro',
      subheadline: 'Subscribe or restore a purchase to create new PDF exports. Your saved PDFs remain available.',
      primary_cta_title: 'View Pro Plans', secondary_cta_title: 'Restore Purchases',
      show_continue_free: false, show_restore_purchases: true,
      recommended_product_id: 'proestimate.pro.monthly', available_products: null,
    });
  }
  // iOS already reserves QUOTE_EXPORT after rendering, before this separate
  // persistence call. Do not double-charge that existing two-step contract.
  const fileSize = Math.floor((input.pdf_data.length * 3) / 4);

  const created = await prisma.estimateExport.create({
    data: {
      estimateId: estimate.id,
      projectId: estimate.projectId,
      fileName: input.file_name,
      contentType: input.content_type ?? 'application/pdf',
      fileSize,
      pdfData: input.pdf_data,
    },
    select: {
      id: true,
      estimateId: true,
      projectId: true,
      fileName: true,
      contentType: true,
      fileSize: true,
      createdAt: true,
    },
  });

  return created;
}

/**
 * List all PDF exports for one estimate, newest first. Excludes `pdfData`
 * so the response stays small.
 */
export async function listByEstimate(estimateId: string, companyId: string) {
  await verifyEstimateOwnership(estimateId, companyId);

  return prisma.estimateExport.findMany({
    where: { estimateId },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      estimateId: true,
      projectId: true,
      fileName: true,
      contentType: true,
      fileSize: true,
      createdAt: true,
    },
  });
}

/**
 * List all PDF exports for every estimate in a project, newest first.
 * Used by the iOS project detail screen to render a unified saved-PDFs
 * list under each estimate row without N round-trips.
 */
export async function listByProject(projectId: string, companyId: string) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
    select: { id: true },
  });

  if (!project) {
    throw new NotFoundError('Project', projectId);
  }

  return prisma.estimateExport.findMany({
    where: { projectId },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      estimateId: true,
      projectId: true,
      fileName: true,
      contentType: true,
      fileSize: true,
      createdAt: true,
    },
  });
}

/**
 * Fetch metadata for a single export, scoped to the requesting company.
 */
export async function getById(id: string, companyId: string) {
  const record = await prisma.estimateExport.findUnique({
    where: { id },
    include: { estimate: { select: { companyId: true } } },
  });

  if (!record || record.estimate.companyId !== companyId) {
    throw new NotFoundError('EstimateExport', id);
  }

  return {
    id: record.id,
    estimateId: record.estimateId,
    projectId: record.projectId,
    fileName: record.fileName,
    contentType: record.contentType,
    fileSize: record.fileSize,
    createdAt: record.createdAt,
  };
}

/**
 * Public (no-auth) binary PDF retrieval. CUID2 IDs are unguessable so this
 * matches the `getPublicAssetImage` pattern used by Asset.imageData. Lets
 * iOS open the PDF in QuickLook / share sheet without juggling auth headers.
 */
export async function getPublicPdf(id: string) {
  const record = await prisma.estimateExport.findUnique({
    where: { id },
    select: { pdfData: true, contentType: true, fileName: true },
  });

  if (!record) {
    return null;
  }

  return {
    data: Buffer.from(record.pdfData, 'base64'),
    contentType: record.contentType,
    fileName: record.fileName,
  };
}

/**
 * Delete an export. Verifies ownership through the estimate→company
 * relation so we never expose another tenant's PDFs.
 */
export async function remove(id: string, companyId: string) {
  const record = await prisma.estimateExport.findUnique({
    where: { id },
    include: { estimate: { select: { companyId: true } } },
  });

  if (!record || record.estimate.companyId !== companyId) {
    throw new NotFoundError('EstimateExport', id);
  }

  await prisma.estimateExport.delete({ where: { id } });
}
