import { Prisma } from '@prisma/client';
import { MAX_ESTIMATE_MONEY } from '../../lib/estimate-money';
import { ConflictError } from '../../lib/errors';
import { proposalDocumentHash } from '../proposals/proposal-document-snapshot';
import { lockContractForEstimate } from './change-order-locks';
import { readChangeOrderBase, toChangeOrderComparison } from './change-order-comparison';

export async function lockChangeOrderProposal(tx:Prisma.TransactionClient,proposalId:string,companyId:string) {
 const order=await tx.changeOrder.findFirst({where:{proposalId,companyId},select:{estimateId:true}});
 if(order) await lockContractForEstimate(tx,order.estimateId,companyId);
}
export async function freezeChangeOrderForSend(tx:Prisma.TransactionClient,proposalId:string,companyId:string) {
 const order=await tx.changeOrder.findFirst({where:{proposalId,companyId},include:{estimate:true,baseEstimate:{include:{proposals:{where:{status:'APPROVED'},orderBy:{createdAt:'desc'}}}}}});
 if(!order) return;
 if(order.status!=='DRAFT') throw new ConflictError('This change order has already been sent. Open its existing version.');
 const base=readChangeOrderBase(order.baseSnapshot);
 const subtotal=order.estimate.subtotalMaterials.plus(order.estimate.subtotalLabor).plus(order.estimate.subtotalOther);
 if(!subtotal.plus(order.estimate.taxAmount).minus(order.estimate.discountAmount).equals(order.estimate.totalAmount)) throw new ConflictError('The revised discount exceeds the priced scope. Review the discount before sending.');
 const signedComponents=[subtotal,subtotal.minus(base.subtotal),order.estimate.taxAmount.minus(base.tax),order.estimate.discountAmount.minus(base.discount),order.estimate.totalAmount.minus(base.total)];
 if(signedComponents.some(value=>value.abs().gt(MAX_ESTIMATE_MONEY))) throw new ConflictError('The amendment exceeds the supported invoice amount. Split this contract into smaller agreements before sending.');
 const original=order.baseEstimate.proposals.find(p=>p.sentSnapshot && proposalDocumentHash(p.sentSnapshot)===base.document_hash);
 if(!original || order.baseEstimate.status!=='APPROVED') throw new ConflictError('The approved source changed. Create a new change order from the current approved contract.');
 const currentProject=await tx.project.findFirst({where:{id:order.projectId,companyId},select:{clientId:true}});
 if(original.sentRecipientClientId && original.sentRecipientClientId!==currentProject?.clientId) throw new ConflictError('The project customer changed after the approved baseline. Restore that customer before sending an amendment.');
 const latest=await tx.changeOrder.findFirst({where:{companyId,rootEstimateId:order.rootEstimateId,status:{in:['APPROVED','APPLIED','INCLUDED']}},orderBy:[{createdAt:'desc'},{id:'desc'}]});
 if(latest && latest.estimateId!==order.baseEstimateId) throw new ConflictError('A newer change order was approved. Start from that approved version.');
 if(!order.baseEstimate.totalAmount.equals(base.total) || !order.baseEstimate.taxAmount.equals(base.tax) || !order.baseEstimate.discountAmount.equals(base.discount) || !order.baseEstimate.subtotalMaterials.plus(order.baseEstimate.subtotalLabor).plus(order.baseEstimate.subtotalOther).equals(base.subtotal)) throw new ConflictError('The approved source prices changed. Contact support before sending.');
 await tx.changeOrder.update({where:{id:order.id},data:{comparisonSnapshot:toChangeOrderComparison(order,order.estimate) as unknown as Prisma.InputJsonObject,status:'SENT'}});
}
export async function recordChangeOrderDecision(tx:Prisma.TransactionClient,proposalId:string,status:'approved'|'declined'|'changes_requested',documentHash:string|null) {
 const order=await tx.changeOrder.findUnique({where:{proposalId}});
 if(!order) return;
 if(status==='changes_requested') {
  await tx.changeOrder.update({where:{id:order.id},data:{status:'CHANGES_REQUESTED'}});
  return;
 }
 if(status==='approved' && !documentHash) throw new ConflictError('Review and sign this exact change order before approval.');
 await tx.changeOrder.update({where:{id:order.id},data:{status:status.toUpperCase(),approvedDocumentHash:status==='approved'?documentHash:null}});
}
