import { randomUUID } from 'node:crypto';
import { ChangeOrder, Prisma } from '@prisma/client';
import { PaginationParams, buildCursorWhere, paginateResults } from '../../lib/pagination';
import { prisma } from '../../config/database';
import { ConflictError, NotFoundError, ValidationError } from '../../lib/errors';
import { calculateEstimateTotals, estimateTotalsMatch } from '../../lib/estimate-money';
import { hashCanonicalValue, proposalDocumentHash, readProposalSnapshot } from '../proposals/proposal-document-snapshot';
import { assertNoActiveCheckout } from '../invoice-checkout/invoice-checkout.policy';
import { toEstimateDto } from '../estimates/estimates.dto';
import { assertCanCreateInvoice } from '../invoices/invoices.service';
import { toInvoiceDto } from '../invoices/invoices.dto';
import { changeOrderDeltas, readChangeOrderBase, toChangeOrderComparison } from './change-order-comparison';
import { estimateFamily, lockContractForEstimate, lockFamilyInvoices } from './change-order-locks';
import { assertOriginalInvoiceBasis } from './change-order-invoice';
import { applyAvailableContractCredits } from './credit-notes.service';

export type CreateChangeOrder={request_id:string;base_estimate_id:string;title:string;reason:string};
async function getOrder(tx:Prisma.TransactionClient,id:string,companyId:string) {
 const result=await tx.changeOrder.findFirst({where:{id,companyId},include:{estimate:true,invoices:true,creditNote:{include:{allocations:true}}}});
 if(!result) throw new NotFoundError('Change order',id);
 return result;
}
export async function get(id:string,companyId:string) {return dto(await getOrder(prisma,id,companyId));}
export async function list(projectId:string,companyId:string,pagination:PaginationParams={}) {
 if(!await prisma.project.findFirst({where:{id:projectId,companyId},select:{id:true}})) throw new NotFoundError('Project',projectId);
 const {cursor,pageSize=25}=pagination;
 const rows=await prisma.changeOrder.findMany({where:{projectId,companyId},orderBy:[{createdAt:'desc'},{id:'desc'}],include:{estimate:true,invoices:true,creditNote:{include:{allocations:true}}},take:pageSize+1,...buildCursorWhere(cursor)});
 const page=paginateResults(rows,pageSize);
 return {...page,items:page.items.map(dto)};
}
function dto(order:Awaited<ReturnType<typeof getOrder>>) {
 const note=order.creditNote;
 return {id:order.id,project_id:order.projectId,root_estimate_id:order.rootEstimateId,base_estimate_id:order.baseEstimateId,estimate_id:order.estimateId,proposal_id:order.proposalId,parent_change_order_id:order.parentChangeOrderId,root_invoice_id:order.rootInvoiceId,status:order.status.toLowerCase(),title:order.title,reason:order.reason,comparison:order.comparisonSnapshot ?? toChangeOrderComparison(order,order.estimate),estimate:toEstimateDto({...order.estimate,changeOrder:{id:order.id}}),invoices:order.invoices.map(toInvoiceDto),credit_note:note?{id:note.id,credit_number:note.creditNumber,amount:Number(note.amount),allocated_amount:Number(note.allocations.reduce((sum,a)=>sum.plus(a.amount),new Prisma.Decimal(0))),currency_code:note.currencyCode,reason:note.reason,created_at:note.createdAt.toISOString()}:null,created_at:order.createdAt.toISOString(),applied_at:order.appliedAt?.toISOString()??null};
}
export async function create(companyId:string,userId:string,data:CreateChangeOrder) {
 return prisma.$transaction(async tx=>{
  await lockContractForEstimate(tx,data.base_estimate_id,companyId);
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`change-order-request:${companyId}:${data.request_id}`},0))`;
  const replay=await tx.changeOrder.findUnique({where:{companyId_requestId:{companyId,requestId:data.request_id}}});
  if(replay) {
   if(replay.baseEstimateId!==data.base_estimate_id || replay.title!==data.title || replay.reason!==data.reason) throw new ConflictError('This request was already used for another change order.');
   return dto(await getOrder(tx,replay.id,companyId));
  }
  await tx.$queryRaw`SELECT id FROM "Estimate" WHERE id=${data.base_estimate_id} AND "companyId"=${companyId} FOR UPDATE`;
  const source=await tx.estimate.findFirst({where:{id:data.base_estimate_id,companyId},include:{lineItems:{orderBy:[{sortOrder:'asc'},{id:'asc'}]},proposals:{where:{status:'APPROVED'},orderBy:{createdAt:'desc'}},project:{select:{clientId:true}}}});
  if(!source) throw new NotFoundError('Estimate',data.base_estimate_id);
  if(source.status!=='APPROVED') throw new ConflictError('Start a change order from an approved estimate.');
  if(!source.project.clientId) throw new ValidationError('Assign the customer before preparing a change order.');
  const proposal=source.proposals.find(p=>p.sentSnapshot!==null);
  if(!proposal) throw new ConflictError('The approved source needs an immutable customer proposal before it can be amended.');
  if(proposal.sentRecipientClientId && proposal.sentRecipientClientId!==source.project.clientId) throw new ConflictError('The project customer changed after approval. Restore the approved customer before amending this contract.');
  const snapshot=readProposalSnapshot(proposal.sentSnapshot);
  if(snapshot.estimate_id!==source.id || snapshot.estimate_version!==source.version || !estimateTotalsMatch(source,calculateEstimateTotals(source.lineItems,source.discountAmount))) throw new ConflictError('The approved source prices need review.');
  const subtotal=source.subtotalMaterials.plus(source.subtotalLabor).plus(source.subtotalOther);
  if(!subtotal.plus(source.taxAmount).minus(source.discountAmount).equals(source.totalAmount)) throw new ConflictError('The approved baseline discount exceeds its priced scope and needs review before amendment.');
  if(!source.totalAmount.equals(snapshot.content.estimate.total_amount) || !source.taxAmount.equals(snapshot.content.estimate.tax_amount) || !source.discountAmount.equals(snapshot.content.estimate.discount_amount)) throw new ConflictError('The approved source differs from the signed customer document.');
  const family=await estimateFamily(tx,source.id,companyId);
  const pending=await tx.changeOrder.findFirst({where:{companyId,rootEstimateId:family.rootEstimateId,status:{in:['DRAFT','SENT']}}});
  if(pending) throw new ConflictError('Finish or decline the pending change order before creating another.');
  const latest=await tx.changeOrder.findFirst({where:{companyId,rootEstimateId:family.rootEstimateId,status:{in:['APPROVED','APPLIED','INCLUDED']}},orderBy:[{createdAt:'desc'},{id:'desc'}]});
  const rootInvoice=await tx.invoice.findFirst({where:{companyId,estimateId:{in:family.estimateIds},sourceChangeOrderId:null,status:{not:'VOID'}},orderBy:[{createdAt:'asc'},{id:'asc'}]});
  if(rootInvoice) {
   if(rootInvoice.clientId!==source.project.clientId) throw new ConflictError("The original invoice belongs to a different customer. Restore that contract customer before creating a change order.");
   await assertOriginalInvoiceBasis(tx,rootInvoice,companyId);
  }
  if(rootInvoice && (rootInvoice.currencyCode??'USD').toUpperCase()!=='USD') throw new ConflictError('Change orders require the same USD contract currency.');
  if(latest ? latest.estimateId!==source.id : rootInvoice && rootInvoice.estimateId!==source.id) throw new ConflictError('Start from the latest approved change order, or the original invoiced contract.');
  const company=await tx.company.update({where:{id:companyId},data:{nextEstimateNumber:{increment:1}},select:{estimatePrefix:true,nextEstimateNumber:true}});
  const estimate=await tx.estimate.create({data:{companyId,projectId:source.projectId,createdByUserId:userId,revisesEstimateId:source.id,estimateNumber:`${company.estimatePrefix||'EST'}-${company.nextEstimateNumber-1}`,version:source.version+1,title:data.title,pricingProfileId:source.pricingProfileId,qualityTier:source.qualityTier,subtotalMaterials:source.subtotalMaterials,subtotalLabor:source.subtotalLabor,subtotalOther:source.subtotalOther,taxAmount:source.taxAmount,discountAmount:source.discountAmount,contingencyAmount:source.contingencyAmount,totalAmount:source.totalAmount,assumptions:source.assumptions,exclusions:source.exclusions,notes:source.notes,validUntil:source.validUntil}});
  const copied=new Map<string,string>();
  for(const item of source.lineItems) {const{id,estimateId,parentLineItemId,...fields}=item;const copy=await tx.estimateLineItem.create({data:{...fields,estimateId:estimate.id}});copied.set(id,copy.id);}
  for(const item of source.lineItems) if(item.parentLineItemId) {const parent=copied.get(item.parentLineItemId);if(!parent)throw new ConflictError('The source item hierarchy needs review.');await tx.estimateLineItem.update({where:{id:copied.get(item.id)!},data:{parentLineItemId:parent}});}
  const nextProposal=await tx.proposal.create({data:{companyId,projectId:source.projectId,estimateId:estimate.id,shareToken:randomUUID(),title:data.title,introText:data.reason,scopeOfWork:proposal.scopeOfWork,timelineText:proposal.timelineText,termsAndConditions:proposal.termsAndConditions,footerText:proposal.footerText}});
  const order=await tx.changeOrder.create({data:{companyId,projectId:source.projectId,rootEstimateId:family.rootEstimateId,baseEstimateId:source.id,estimateId:estimate.id,proposalId:nextProposal.id,requestId:data.request_id,parentChangeOrderId:latest?.id,rootInvoiceId:rootInvoice?.id,title:data.title,reason:data.reason,createdByUserId:userId,baseSnapshot:{estimate_id:source.id,estimate_number:source.estimateNumber,version:source.version,document_hash:proposalDocumentHash(proposal.sentSnapshot),subtotal:subtotal.toFixed(2),tax:source.taxAmount.toFixed(2),discount:source.discountAmount.toFixed(2),total:source.totalAmount.toFixed(2),scope:{line_items:snapshot.content.estimate.line_items.map(i=>({name:i.name,description:i.description,quantity:i.quantity,unit:i.unit,line_total:i.line_total})),assumptions:snapshot.content.estimate.assumptions??null,exclusions:snapshot.content.estimate.exclusions??null}}}});
  return dto(await getOrder(tx,order.id,companyId));
 },{timeout:15000});
}

/** Apply every approved ancestor exactly once, in contract order. A positive
 * amendment bills only signed component deltas; credit never rewrites cash.
 */
export async function apply(id:string,companyId:string,userId:string,requestId:string) {
 await assertCanCreateInvoice(userId);
 return prisma.$transaction(async tx=>{
  const initial=await getOrder(tx,id,companyId);
  await lockContractForEstimate(tx,initial.estimateId,companyId);
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`change-order-apply:${companyId}:${requestId}`},0))`;
  const receipt=await tx.changeOrderApplyRequest.findUnique({where:{companyId_requestId:{companyId,requestId}}});
  if(receipt && receipt.changeOrderId!==id) throw new ConflictError('This apply request was already used for another change order.');
  if(receipt) return dto(await getOrder(tx,id,companyId));
  const order=await getOrder(tx,id,companyId);
  if(!['APPROVED','APPLIED','INCLUDED'].includes(order.status)) throw new ConflictError('The customer must approve this exact change order before applying it.');
  const chain:ChangeOrder[]=[];let cursor:ChangeOrder|null=order;const seen=new Set<string>();
  while(cursor) {if(seen.has(cursor.id)||seen.size>=1000) throw new ConflictError('The amendment history needs review.');seen.add(cursor.id);chain.unshift(cursor);const parentId=cursor.parentChangeOrderId;cursor=parentId?await tx.changeOrder.findFirst({where:{id:parentId,companyId,rootEstimateId:order.rootEstimateId}}):null;if(parentId&&!cursor)throw new ConflictError('The amendment parent history could not be verified.');}
  const family=await estimateFamily(tx,order.estimateId,companyId);
  for(const invoiceId of await lockFamilyInvoices(tx,companyId,family.estimateIds)) await assertNoActiveCheckout(tx,invoiceId);
  const rootInvoice=await tx.invoice.findFirst({where:{companyId,estimateId:{in:family.estimateIds},sourceChangeOrderId:null,status:{not:'VOID'}},orderBy:[{createdAt:'asc'},{id:'asc'}]});
  if(!rootInvoice) throw new ConflictError('Create the first invoice from the latest approved contract. Its change orders will be included in that full invoice.');
  await assertOriginalInvoiceBasis(tx,rootInvoice,companyId);
  if((rootInvoice.currencyCode??'USD').toUpperCase()!=='USD') throw new ConflictError('The contract invoice currency needs review.');
  for(const amendment of chain) {
   if(['APPLIED','INCLUDED'].includes(amendment.status)) continue;
   if(amendment.status!=='APPROVED') throw new ConflictError('Approve earlier change orders before applying this change.');
   const revised=await tx.estimate.findUniqueOrThrow({where:{id:amendment.estimateId},include:{lineItems:true}});
   const offer=await tx.proposal.findUniqueOrThrow({where:{id:amendment.proposalId},include:{acceptance:true}});
   if(!offer.sentSnapshot || offer.status!=='APPROVED' || !offer.acceptance || offer.acceptance.documentHash!==amendment.approvedDocumentHash || proposalDocumentHash(offer.sentSnapshot)!==amendment.approvedDocumentHash) throw new ConflictError('The signed amendment version could not be verified.');
   if(offer.sentRecipientClientId && offer.sentRecipientClientId!==rootInvoice.clientId) throw new ConflictError('The approved change order belongs to a different customer than the original invoice.');
   const saved=readProposalSnapshot(offer.sentSnapshot).content as unknown as {change_order?:unknown};
   if(!saved.change_order || hashCanonicalValue(saved.change_order)!==hashCanonicalValue(amendment.comparisonSnapshot) || hashCanonicalValue(toChangeOrderComparison(amendment,revised))!==hashCanonicalValue(amendment.comparisonSnapshot)) throw new ConflictError('The approved amendment price or source changed.');
   if(!estimateTotalsMatch(revised,calculateEstimateTotals(revised.lineItems,revised.discountAmount))) throw new ConflictError('The approved amendment prices need review.');
   const delta=changeOrderDeltas(amendment,revised);
   if(!delta.subtotal.plus(delta.tax).minus(delta.discount).equals(delta.total)) throw new ConflictError('The amendment totals do not reconcile.');
   if(delta.total.gt(0)) {
    const company=await tx.company.update({where:{id:companyId},data:{nextInvoiceNumber:{increment:1}},select:{invoicePrefix:true,nextInvoiceNumber:true}});
    const invoice=await tx.invoice.create({data:{companyId,projectId:amendment.projectId,clientId:rootInvoice.clientId,estimateId:amendment.estimateId,proposalId:amendment.proposalId,sourceChangeOrderId:amendment.id,rootInvoiceId:rootInvoice.id,financialBasisLocked:true,invoiceNumber:`${company.invoicePrefix||'INV'}-${company.nextInvoiceNumber-1}`,subtotal:delta.subtotal,taxAmount:delta.tax,discountAmount:delta.discount,totalAmount:delta.total,amountDue:delta.total,currencyCode:'USD',notes:`Approved change order: ${amendment.title}. Base ${readChangeOrderBase(amendment.baseSnapshot).total}; revised ${revised.totalAmount.toFixed(2)}. This invoice bills only the additional amount.`}});
    await tx.invoiceLineItem.create({data:{invoiceId:invoice.id,name:`Change order: ${amendment.title}`,description:amendment.reason,quantity:1,unit:'change',unitCost:delta.subtotal,lineTotal:delta.subtotal,taxRate:0}});
   } else if(delta.total.lt(0)) {
    await tx.creditNote.create({data:{companyId,projectId:amendment.projectId,rootEstimateId:order.rootEstimateId,sourceChangeOrderId:amendment.id,creditNumber:`CN-${amendment.id}`,amount:delta.total.negated(),subtotalDelta:delta.subtotal,taxDelta:delta.tax,discountDelta:delta.discount,currencyCode:'USD',reason:amendment.reason}});
   }
   await tx.changeOrder.update({where:{id:amendment.id},data:{status:'APPLIED',rootInvoiceId:rootInvoice.id,appliedAt:new Date()}});
  }
  await applyAvailableContractCredits(tx,companyId,order.rootEstimateId);
  await tx.changeOrderApplyRequest.create({data:{companyId,requestId,changeOrderId:id}});
  await tx.activityLogEntry.create({data:{projectId:order.projectId,userId,action:'INVOICE_CREATED',description:`Approved change order applied: ${order.title}`}});
  return dto(await getOrder(tx,id,companyId));
 },{timeout:15000});
}
