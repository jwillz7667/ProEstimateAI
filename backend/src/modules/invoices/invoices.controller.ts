import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { parsePagination } from '../../lib/pagination';
import { param } from '../../lib/params';
import * as invoicesService from './invoices.service';
import { toInvoiceDto } from './invoices.dto';

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });
  const projectId = req.query.project_id as string | undefined;
  const result = await invoicesService.list(req.companyId!, pagination, projectId);

  sendSuccess(
    res,
    result.items.map(toInvoiceDto),
    { pagination: { next_cursor: result.nextCursor } }
  );
}

export async function getByIdHandler(req: Request, res: Response) {
  const invoice = await invoicesService.getById(param(req.params.id), req.companyId!);
  sendSuccess(res, toInvoiceDto(invoice));
}

export async function createHandler(req: Request, res: Response) {
  const invoice = await invoicesService.create(req.companyId!, req.userId!, req.body);
  sendSuccess(res, toInvoiceDto(invoice), { statusCode: 201 });
}

export async function updateHandler(req: Request, res: Response) {
  const invoice = await invoicesService.update(param(req.params.id), req.companyId!, req.body);
  sendSuccess(res, toInvoiceDto(invoice));
}

export async function sendHandler(req: Request, res: Response) {
  const invoice = await invoicesService.send(param(req.params.id), req.companyId!, req.userId!);
  sendSuccess(res, toInvoiceDto(invoice));
}

export async function deleteHandler(req: Request, res: Response) {
  await invoicesService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}

export async function exportPDFHandler(req: Request, res: Response) {
  const { generateInvoicePDF } = await import('../pdf/pdf.service');
  const pdfBuffer = await generateInvoicePDF(param(req.params.id), req.companyId!, req.userId!);
  res.set('Content-Type', 'application/pdf');
  res.set('Content-Disposition', `attachment; filename="invoice-${req.params.id}.pdf"`);
  res.set('Cache-Control', 'private, no-cache');
  res.send(pdfBuffer);
}
