import { Prisma } from '@prisma/client';
import { estimateFamily, lockFamilyInvoices } from './change-order-locks';
import { invoiceAmountDue } from '../invoice-finance/invoice-balance';

/** Caller owns the contract mutex. No invoice is locked after note rows.
 * Active checkout balances stay frozen so verified refunds can still commit.
 * New collection paths reconcile again before reserving a fresh balance.
 */
export async function applyAvailableContractCredits(tx: Prisma.TransactionClient, companyId: string, rootEstimateId: string): Promise<void> {
  const family = await estimateFamily(tx, rootEstimateId, companyId);
  await lockFamilyInvoices(tx, companyId, family.estimateIds);
  await tx.$queryRaw`SELECT id FROM "CreditNote" WHERE "companyId"=${companyId} AND "rootEstimateId"=${rootEstimateId} ORDER BY id FOR UPDATE`;
  const notes = await tx.creditNote.findMany({ where: { companyId, rootEstimateId }, orderBy: [{createdAt:'asc'},{id:'asc'}], include: {allocations:true} });
  const invoices = await tx.invoice.findMany({ where: {companyId,estimateId:{in:family.estimateIds},status:{not:'VOID'}}, orderBy:[{createdAt:'asc'},{id:'asc'}], include: {checkoutAttempts:{where:{state:{in:['PREPARING','OPEN','PROCESSING']}},select:{id:true}}} });
  for (const note of notes) {
    let available = note.amount.minus(note.allocations.reduce((sum,a)=>sum.plus(a.amount),new Prisma.Decimal(0)));
    for (const invoice of invoices) {
      if (available.lte(0)) break;
      if (invoice.checkoutAttempts.length || (invoice.currencyCode ?? 'USD').toUpperCase() !== note.currencyCode) continue;
      const due=invoiceAmountDue(invoice.totalAmount,invoice.amountPaid,invoice.creditAmount);
      if (due.lte(0)) continue;
      const applied=Prisma.Decimal.min(available,due);
      await tx.creditAllocation.create({data:{creditNoteId:note.id,invoiceId:invoice.id,amount:applied}});
      invoice.creditAmount=invoice.creditAmount.plus(applied);
      const amountDue=invoiceAmountDue(invoice.totalAmount,invoice.amountPaid,invoice.creditAmount);
      const status=invoice.status==='DRAFT'?'DRAFT':amountDue.isZero()?'PAID':invoice.amountPaid.gt(0)?'PARTIALLY_PAID':invoice.status==='PAID'?'SENT':invoice.status;
      await tx.invoice.update({where:{id:invoice.id},data:{creditAmount:invoice.creditAmount,amountDue,status,paidAt:status==='PAID'?(invoice.paidAt??new Date()):null}});
      available=available.minus(applied);
    }
  }
}
