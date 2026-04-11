import PDFDocument from 'pdfkit';
import { prisma } from '../../config/database';
import { NotFoundError, AuthorizationError } from '../../lib/errors';

// ─── Typography ──────────────────────────────────────────
const FONT_TITLE = 20;
const FONT_HEADER = 14;
const FONT_SUBHEADER = 12;
const FONT_BODY = 10;
const FONT_SMALL = 8;

// ─── Colors ──────────────────────────────────────────────
const COLOR_PRIMARY = '#F97316';
const COLOR_TEXT = '#1A1A1A';
const COLOR_MUTED = '#6B7280';
const COLOR_BORDER = '#E5E7EB';
const COLOR_TABLE_HEADER_BG = '#F3F4F6';
const COLOR_WATERMARK = '#D1D5DB';

// ─── Layout ──────────────────────────────────────────────
const PAGE_MARGIN = 50;
const TABLE_COL_ITEM = PAGE_MARGIN;
const TABLE_COL_QTY = 310;
const TABLE_COL_UNIT = 360;
const TABLE_COL_RATE = 410;
const TABLE_COL_TOTAL = 475;
const TABLE_RIGHT_EDGE = 545;

// ─── Helpers ─────────────────────────────────────────────

function formatCurrency(value: number | string | { toNumber?: () => number }): string {
  const num = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? parseFloat(value)
      : typeof value === 'object' && value !== null && 'toNumber' in value
        ? (value as { toNumber: () => number }).toNumber()
        : 0;
  return `$${num.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
}

function toNumber(value: number | string | { toNumber?: () => number }): number {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return parseFloat(value) || 0;
  if (typeof value === 'object' && value !== null && 'toNumber' in value) {
    return (value as { toNumber: () => number }).toNumber();
  }
  return 0;
}

function formatDate(date: Date | null | undefined): string {
  if (!date) return 'N/A';
  return new Date(date).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

/** Draw a thin horizontal rule at the current Y. */
function drawHR(doc: PDFKit.PDFDocument, y: number): void {
  doc.strokeColor(COLOR_BORDER).lineWidth(0.5)
    .moveTo(PAGE_MARGIN, y)
    .lineTo(TABLE_RIGHT_EDGE, y)
    .stroke();
}

/** Check if we need a new page — returns the Y position to continue at. */
function ensureSpace(doc: PDFKit.PDFDocument, needed: number, currentY: number): number {
  const pageBottom = doc.page.height - PAGE_MARGIN - 30; // leave room for footer
  if (currentY + needed > pageBottom) {
    doc.addPage();
    return PAGE_MARGIN;
  }
  return currentY;
}

// ─── Watermark ───────────────────────────────────────────

function applyWatermark(doc: PDFKit.PDFDocument): void {
  const pageCount = doc.bufferedPageRange();
  for (let i = 0; i < pageCount.count; i++) {
    doc.switchToPage(pageCount.start + i);
    doc.save();

    const centerX = doc.page.width / 2;
    const centerY = doc.page.height / 2;

    doc.translate(centerX, centerY);
    doc.rotate(45, { origin: [0, 0] });

    doc.fontSize(60)
      .fillColor(COLOR_WATERMARK)
      .opacity(0.15)
      .text('Created with ProEstimate AI', 0, 0, {
        align: 'center',
        width: 600,
        lineBreak: false,
      });

    doc.restore();
    doc.opacity(1);
  }
}

/** Check whether the user's plan allows watermark removal. */
async function shouldApplyWatermark(userId: string): Promise<boolean> {
  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId },
    include: { plan: { select: { featuresJson: true } } },
  });

  if (!entitlement) return true;

  const features = entitlement.plan.featuresJson as Record<string, unknown>;
  const canRemove = features.CAN_REMOVE_WATERMARK === true;

  const activeStatuses = [
    'TRIAL_ACTIVE',
    'PRO_ACTIVE',
    'GRACE_PERIOD',
    'BILLING_RETRY',
    'CANCELED_ACTIVE',
    'ADMIN_OVERRIDE',
  ];
  const isActive = activeStatuses.includes(entitlement.status);

  return !(canRemove && isActive);
}

// ─── Company Header (shared between proposal & invoice) ──

function drawCompanyHeader(
  doc: PDFKit.PDFDocument,
  company: { name: string; address?: string | null; city?: string | null; state?: string | null; zip?: string | null; phone?: string | null; email?: string | null; websiteUrl?: string | null },
): number {
  let y = PAGE_MARGIN;

  // Company name
  doc.fontSize(FONT_TITLE).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
    .text(company.name, PAGE_MARGIN, y, { width: 300 });
  y += 28;

  doc.fontSize(FONT_SMALL).fillColor(COLOR_MUTED).font('Helvetica');

  const addressParts: string[] = [];
  if (company.address) addressParts.push(company.address);
  const cityStateZip = [company.city, company.state].filter(Boolean).join(', ');
  if (cityStateZip || company.zip) {
    addressParts.push([cityStateZip, company.zip].filter(Boolean).join(' '));
  }
  if (addressParts.length > 0) {
    doc.text(addressParts.join('\n'), PAGE_MARGIN, y);
    y += addressParts.length * 12;
  }

  if (company.phone) {
    doc.text(company.phone, PAGE_MARGIN, y);
    y += 12;
  }
  if (company.email) {
    doc.text(company.email, PAGE_MARGIN, y);
    y += 12;
  }
  if (company.websiteUrl) {
    doc.text(company.websiteUrl, PAGE_MARGIN, y);
    y += 12;
  }

  y += 8;
  drawHR(doc, y);
  y += 12;

  return y;
}

// ─── Line Item Table Rendering ───────────────────────────

interface TableLineItem {
  name: string;
  description?: string | null;
  quantity: number | string | { toNumber?: () => number };
  unit: string;
  unitCost: number | string | { toNumber?: () => number };
  lineTotal: number | string | { toNumber?: () => number };
}

function drawTableHeader(doc: PDFKit.PDFDocument, y: number): number {
  // Header background
  doc.rect(PAGE_MARGIN, y, TABLE_RIGHT_EDGE - PAGE_MARGIN, 20)
    .fill(COLOR_TABLE_HEADER_BG);

  const headerY = y + 5;
  doc.fontSize(FONT_SMALL).fillColor(COLOR_TEXT).font('Helvetica-Bold');
  doc.text('Item', TABLE_COL_ITEM + 6, headerY, { width: 250 });
  doc.text('Qty', TABLE_COL_QTY, headerY, { width: 45, align: 'right' });
  doc.text('Unit', TABLE_COL_UNIT, headerY, { width: 45, align: 'center' });
  doc.text('Rate', TABLE_COL_RATE, headerY, { width: 60, align: 'right' });
  doc.text('Total', TABLE_COL_TOTAL, headerY, { width: 70, align: 'right' });

  return y + 24;
}

function drawTableRow(doc: PDFKit.PDFDocument, item: TableLineItem, y: number): number {
  y = ensureSpace(doc, 28, y);

  doc.font('Helvetica').fontSize(FONT_BODY).fillColor(COLOR_TEXT);
  doc.text(item.name, TABLE_COL_ITEM + 6, y, { width: 250 });
  doc.text(toNumber(item.quantity).toString(), TABLE_COL_QTY, y, { width: 45, align: 'right' });
  doc.text(item.unit, TABLE_COL_UNIT, y, { width: 45, align: 'center' });
  doc.text(formatCurrency(item.unitCost), TABLE_COL_RATE, y, { width: 60, align: 'right' });
  doc.text(formatCurrency(item.lineTotal), TABLE_COL_TOTAL, y, { width: 70, align: 'right' });

  let rowHeight = 16;

  if (item.description) {
    doc.fontSize(FONT_SMALL).fillColor(COLOR_MUTED);
    doc.text(item.description, TABLE_COL_ITEM + 6, y + 14, { width: 250 });
    rowHeight += 12;
  }

  // Light bottom border
  const lineY = y + rowHeight + 2;
  doc.strokeColor(COLOR_BORDER).lineWidth(0.3)
    .moveTo(PAGE_MARGIN, lineY)
    .lineTo(TABLE_RIGHT_EDGE, lineY)
    .stroke();

  return lineY + 4;
}

/** Draw a right-aligned summary row (e.g. Subtotal, Tax, Total). */
function drawSummaryRow(
  doc: PDFKit.PDFDocument,
  label: string,
  value: string,
  y: number,
  options?: { bold?: boolean; fontSize?: number },
): number {
  const bold = options?.bold ?? false;
  const fontSize = options?.fontSize ?? FONT_BODY;

  doc.font(bold ? 'Helvetica-Bold' : 'Helvetica')
    .fontSize(fontSize)
    .fillColor(COLOR_TEXT);

  doc.text(label, TABLE_COL_RATE - 80, y, { width: 140, align: 'right' });
  doc.text(value, TABLE_COL_TOTAL, y, { width: 70, align: 'right' });

  return y + fontSize + 6;
}

// ─── Footer ──────────────────────────────────────────────

function drawPageFooter(doc: PDFKit.PDFDocument, text?: string): void {
  const range = doc.bufferedPageRange();
  for (let i = 0; i < range.count; i++) {
    doc.switchToPage(range.start + i);
    const pageBottom = doc.page.height - 30;

    doc.fontSize(FONT_SMALL).fillColor(COLOR_MUTED).font('Helvetica');

    if (text) {
      doc.text(text, PAGE_MARGIN, pageBottom - 12, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        align: 'center',
      });
    }

    doc.text(
      `Page ${i + 1} of ${range.count}`,
      PAGE_MARGIN,
      pageBottom,
      { width: TABLE_RIGHT_EDGE - PAGE_MARGIN, align: 'center' },
    );
  }
}

// ─── Proposal PDF ────────────────────────────────────────

export async function generateProposalPDF(
  proposalId: string,
  companyId: string,
  userId: string,
): Promise<Buffer> {
  const proposal = await prisma.proposal.findFirst({
    where: { id: proposalId },
    include: {
      estimate: { include: { lineItems: { orderBy: { sortOrder: 'asc' } } } },
      project: true,
      company: true,
    },
  });

  if (!proposal) {
    throw new NotFoundError('Proposal', proposalId);
  }

  if (proposal.companyId !== companyId) {
    throw new AuthorizationError('You do not have access to this proposal');
  }

  const needsWatermark = await shouldApplyWatermark(userId);

  const doc = new PDFDocument({ margin: PAGE_MARGIN, bufferPages: true });
  const chunks: Buffer[] = [];
  doc.on('data', (chunk: Buffer) => chunks.push(chunk));
  const finished = new Promise<Buffer>((resolve) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
  });

  // ── Page 1: Company header + Proposal info ──
  let y = drawCompanyHeader(doc, proposal.company);

  // Proposal title
  const proposalTitle = proposal.title || `Proposal ${proposal.proposalNumber || ''}`;
  doc.fontSize(FONT_TITLE).fillColor(COLOR_TEXT).font('Helvetica-Bold')
    .text(proposalTitle, PAGE_MARGIN, y, { width: TABLE_RIGHT_EDGE - PAGE_MARGIN });
  y += 30;

  // Proposal metadata
  doc.fontSize(FONT_BODY).fillColor(COLOR_MUTED).font('Helvetica');

  if (proposal.proposalNumber) {
    doc.text(`Proposal #: ${proposal.proposalNumber}`, PAGE_MARGIN, y);
    y += 14;
  }

  doc.text(`Project: ${proposal.project.title}`, PAGE_MARGIN, y);
  y += 14;

  doc.text(`Date: ${formatDate(proposal.createdAt)}`, PAGE_MARGIN, y);
  y += 14;

  if (proposal.expiresAt) {
    doc.text(`Valid Until: ${formatDate(proposal.expiresAt)}`, PAGE_MARGIN, y);
    y += 14;
  }

  y += 8;
  drawHR(doc, y);
  y += 16;

  // ── Intro Text ──
  if (proposal.introText) {
    y = ensureSpace(doc, 60, y);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Introduction', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_BODY).fillColor(COLOR_TEXT).font('Helvetica')
      .text(proposal.introText, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 3,
      });
    y = doc.y + 16;
  }

  // ── Scope of Work ──
  if (proposal.scopeOfWork) {
    y = ensureSpace(doc, 60, y);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Scope of Work', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_BODY).fillColor(COLOR_TEXT).font('Helvetica')
      .text(proposal.scopeOfWork, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 3,
      });
    y = doc.y + 16;
  }

  // ── Timeline ──
  if (proposal.timelineText) {
    y = ensureSpace(doc, 60, y);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Timeline', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_BODY).fillColor(COLOR_TEXT).font('Helvetica')
      .text(proposal.timelineText, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 3,
      });
    y = doc.y + 16;
  }

  // ── Estimate Table ──
  if (proposal.estimate) {
    y = ensureSpace(doc, 80, y);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Cost Estimate', PAGE_MARGIN, y);
    y += 22;

    const lineItems = proposal.estimate.lineItems;

    // Group by category
    const categories: Array<{ label: string; key: string }> = [
      { label: 'Materials', key: 'MATERIALS' },
      { label: 'Labor', key: 'LABOR' },
      { label: 'Other', key: 'OTHER' },
    ];

    for (const cat of categories) {
      const items = lineItems.filter((li) => li.category === cat.key);
      if (items.length === 0) continue;

      y = ensureSpace(doc, 40, y);
      doc.fontSize(FONT_SUBHEADER).fillColor(COLOR_TEXT).font('Helvetica-Bold')
        .text(cat.label, PAGE_MARGIN, y);
      y += 18;

      y = drawTableHeader(doc, y);

      for (const item of items) {
        y = drawTableRow(doc, {
          name: item.name,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          unitCost: item.unitCost,
          lineTotal: item.lineTotal,
        }, y);
      }

      y += 4;
    }

    // ── Totals ──
    y = ensureSpace(doc, 80, y);
    y += 8;
    drawHR(doc, y);
    y += 10;

    const estimate = proposal.estimate;

    if (toNumber(estimate.subtotalMaterials) > 0) {
      y = drawSummaryRow(doc, 'Materials Subtotal', formatCurrency(estimate.subtotalMaterials), y);
    }
    if (toNumber(estimate.subtotalLabor) > 0) {
      y = drawSummaryRow(doc, 'Labor Subtotal', formatCurrency(estimate.subtotalLabor), y);
    }
    if (toNumber(estimate.subtotalOther) > 0) {
      y = drawSummaryRow(doc, 'Other Subtotal', formatCurrency(estimate.subtotalOther), y);
    }

    if (toNumber(estimate.taxAmount) > 0) {
      y = drawSummaryRow(doc, 'Tax', formatCurrency(estimate.taxAmount), y);
    }

    if (toNumber(estimate.discountAmount) > 0) {
      y = drawSummaryRow(doc, 'Discount', `-${formatCurrency(estimate.discountAmount)}`, y);
    }

    y += 4;
    drawHR(doc, y);
    y += 8;

    y = drawSummaryRow(doc, 'Total', formatCurrency(estimate.totalAmount), y, {
      bold: true,
      fontSize: FONT_HEADER,
    });
  }

  // ── Terms and Conditions ──
  if (proposal.termsAndConditions) {
    y = ensureSpace(doc, 60, y + 16);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Terms & Conditions', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_SMALL).fillColor(COLOR_MUTED).font('Helvetica')
      .text(proposal.termsAndConditions, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 2,
      });
    y = doc.y + 16;
  }

  // ── Footer text ──
  const footerText = proposal.footerText || undefined;

  // Apply watermark + page footer before finalizing
  if (needsWatermark) {
    applyWatermark(doc);
  }
  drawPageFooter(doc, footerText);

  doc.end();
  return finished;
}

// ─── Invoice PDF ─────────────────────────────────────────

export async function generateInvoicePDF(
  invoiceId: string,
  companyId: string,
  userId: string,
): Promise<Buffer> {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId },
    include: {
      lineItems: { orderBy: { sortOrder: 'asc' } },
      project: true,
      company: true,
      client: true,
    },
  });

  if (!invoice) {
    throw new NotFoundError('Invoice', invoiceId);
  }

  if (invoice.companyId !== companyId) {
    throw new AuthorizationError('You do not have access to this invoice');
  }

  const needsWatermark = await shouldApplyWatermark(userId);

  const doc = new PDFDocument({ margin: PAGE_MARGIN, bufferPages: true });
  const chunks: Buffer[] = [];
  doc.on('data', (chunk: Buffer) => chunks.push(chunk));
  const finished = new Promise<Buffer>((resolve) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
  });

  // ── Company Header ──
  let y = drawCompanyHeader(doc, invoice.company);

  // ── INVOICE Title + Number ──
  doc.fontSize(FONT_TITLE + 4).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
    .text('INVOICE', PAGE_MARGIN, y);

  // Invoice number right-aligned on same line
  doc.fontSize(FONT_HEADER).fillColor(COLOR_TEXT).font('Helvetica-Bold')
    .text(invoice.invoiceNumber, PAGE_MARGIN, y + 6, {
      width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
      align: 'right',
    });
  y += 36;

  // ── Invoice metadata (left) + Bill To (right) ──
  const metaStartY = y;

  // Left column: invoice details
  doc.fontSize(FONT_BODY).fillColor(COLOR_MUTED).font('Helvetica');

  doc.text(`Issue Date: ${formatDate(invoice.issuedDate)}`, PAGE_MARGIN, y);
  y += 14;
  doc.text(`Due Date: ${formatDate(invoice.dueDate)}`, PAGE_MARGIN, y);
  y += 14;
  doc.text(`Project: ${invoice.project.title}`, PAGE_MARGIN, y);
  y += 14;

  const statusLabel = invoice.status.replace(/_/g, ' ');
  doc.text(`Status: ${statusLabel}`, PAGE_MARGIN, y);
  y += 14;

  // Right column: Bill To
  const billToX = 340;
  let billToY = metaStartY;

  doc.fontSize(FONT_SUBHEADER).fillColor(COLOR_TEXT).font('Helvetica-Bold')
    .text('Bill To', billToX, billToY);
  billToY += 16;

  doc.fontSize(FONT_BODY).fillColor(COLOR_TEXT).font('Helvetica');
  doc.text(invoice.client.name, billToX, billToY, { width: 200 });
  billToY += 14;

  if (invoice.client.address) {
    doc.text(invoice.client.address, billToX, billToY, { width: 200 });
    billToY += 14;
  }

  const clientCityStateZip = [invoice.client.city, invoice.client.state]
    .filter(Boolean).join(', ');
  const clientLocale = [clientCityStateZip, invoice.client.zip].filter(Boolean).join(' ');
  if (clientLocale) {
    doc.text(clientLocale, billToX, billToY, { width: 200 });
    billToY += 14;
  }

  if (invoice.client.email) {
    doc.text(invoice.client.email, billToX, billToY, { width: 200 });
    billToY += 14;
  }

  if (invoice.client.phone) {
    doc.text(invoice.client.phone, billToX, billToY, { width: 200 });
    billToY += 14;
  }

  y = Math.max(y, billToY) + 12;
  drawHR(doc, y);
  y += 16;

  // ── Line Items Table ──
  y = drawTableHeader(doc, y);

  for (const item of invoice.lineItems) {
    y = drawTableRow(doc, {
      name: item.name,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      unitCost: item.unitCost,
      lineTotal: item.lineTotal,
    }, y);
  }

  // ── Totals ──
  y = ensureSpace(doc, 100, y);
  y += 8;
  drawHR(doc, y);
  y += 10;

  y = drawSummaryRow(doc, 'Subtotal', formatCurrency(invoice.subtotal), y);

  if (toNumber(invoice.taxAmount) > 0) {
    y = drawSummaryRow(doc, 'Tax', formatCurrency(invoice.taxAmount), y);
  }

  if (toNumber(invoice.discountAmount) > 0) {
    y = drawSummaryRow(doc, 'Discount', `-${formatCurrency(invoice.discountAmount)}`, y);
  }

  y += 2;
  drawHR(doc, y);
  y += 8;

  y = drawSummaryRow(doc, 'Total', formatCurrency(invoice.totalAmount), y, {
    bold: true,
    fontSize: FONT_HEADER,
  });

  y += 4;

  if (toNumber(invoice.amountPaid) > 0) {
    y = drawSummaryRow(doc, 'Amount Paid', formatCurrency(invoice.amountPaid), y);
  }

  const amountDueValue = toNumber(invoice.amountDue);
  if (amountDueValue > 0) {
    y = drawSummaryRow(doc, 'Amount Due', formatCurrency(invoice.amountDue), y, {
      bold: true,
      fontSize: FONT_SUBHEADER,
    });
  }

  // ── Payment Instructions ──
  if (invoice.paymentInstructions) {
    y = ensureSpace(doc, 60, y + 16);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Payment Instructions', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_BODY).fillColor(COLOR_TEXT).font('Helvetica')
      .text(invoice.paymentInstructions, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 3,
      });
    y = doc.y + 16;
  }

  // ── Notes ──
  if (invoice.notes) {
    y = ensureSpace(doc, 60, y);
    doc.fontSize(FONT_HEADER).fillColor(COLOR_PRIMARY).font('Helvetica-Bold')
      .text('Notes', PAGE_MARGIN, y);
    y += 20;

    doc.fontSize(FONT_BODY).fillColor(COLOR_MUTED).font('Helvetica')
      .text(invoice.notes, PAGE_MARGIN, y, {
        width: TABLE_RIGHT_EDGE - PAGE_MARGIN,
        lineGap: 2,
      });
    y = doc.y + 16;
  }

  // Apply watermark + page footer before finalizing
  if (needsWatermark) {
    applyWatermark(doc);
  }
  drawPageFooter(doc, 'Thank you for your business.');

  doc.end();
  return finished;
}
