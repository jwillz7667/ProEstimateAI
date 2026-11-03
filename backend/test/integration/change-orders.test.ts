import {randomUUID} from 'node:crypto';
import {beforeEach,describe,expect,it} from 'vitest';
import {prisma} from '../../src/config/database';
import * as estimates from '../../src/modules/estimates/estimates.service';
import * as items from '../../src/modules/estimate-line-items/estimate-line-items.service';
import * as proposals from '../../src/modules/proposals/proposals.service';
import * as invoices from '../../src/modules/invoices/invoices.service';
import * as finance from '../../src/modules/invoice-finance/invoice-finance.service';
import * as orders from '../../src/modules/change-orders/change-orders.service';
import {proposalDocumentHash} from '../../src/modules/proposals/proposal-document-snapshot';
import {lockContractForInvoice} from '../../src/modules/change-orders/change-order-locks';
import {applyAvailableContractCredits} from '../../src/modules/change-orders/credit-notes.service';

beforeEach(async()=>{await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company", "Plan" RESTART IDENTITY CASCADE');});
async function approve(proposalId:string,companyId:string,userId:string) {
 const draft=await proposals.getById(proposalId,companyId);
 await proposals.send(proposalId,companyId,userId,{draft_review_token:draft.draftReviewToken??undefined,expected_estimate_updated_at:draft.estimate.updatedAt.toISOString()});
 const sent=await proposals.getById(proposalId,companyId);
 await proposals.respondToProposal(sent.shareToken!,{decision:'approved',signer_name:'Customer',acceptance_consent:true,consent_version:'quote-acceptance-v1',document_hash:proposalDocumentHash(sent.sentSnapshot)});
}
async function fixture(options:{invoice?:boolean;tax?:number;discount?:number;concession?:number}={}) {
 const company=await prisma.company.create({data:{name:'Change order tests'}});
 const user=await prisma.user.create({data:{companyId:company.id,email:`${randomUUID()}@example.test`,fullName:'Estimator'}});
 const plan=await prisma.plan.create({data:{code:'PRO_MONTHLY',displayName:'Pro',description:'Invoice access',featuresJson:{CAN_CREATE_INVOICE:true}}});
 await prisma.userEntitlement.create({data:{companyId:company.id,userId:user.id,planId:plan.id,status:'PRO_ACTIVE',renewalDate:new Date(Date.now()+86400000)}});
 const client=await prisma.client.create({data:{companyId:company.id,name:'Customer',email:'customer@example.test'}});
 const project=await prisma.project.create({data:{companyId:company.id,clientId:client.id,title:'Kitchen',projectType:'KITCHEN'}});
 const estimate=await estimates.create(company.id,user.id,{project_id:project.id});
 await items.create(estimate.id,company.id,{category:'materials',name:'Cabinets',quantity:1,unit:'job',unit_cost:100,tax_rate:options.tax??0,markup_percent:0,sort_order:0});
 if(options.discount) await estimates.update(estimate.id,company.id,user.id,{discount_amount:options.discount});
 const proposal=await proposals.create(company.id,{estimate_id:estimate.id});
 await approve(proposal.id,company.id,user.id);
 const invoice=options.invoice===false?null:await invoices.createFromEstimate(company.id,user.id,estimate.id,{});
 if(invoice && options.concession) await prisma.invoice.update({where:{id:invoice.id},data:{discountAmount:invoice.discountAmount.plus(options.concession),totalAmount:invoice.totalAmount.minus(options.concession),amountDue:invoice.totalAmount.minus(options.concession),financialBasisLocked:false}});
 return{company,user,client,project,estimate,proposal,invoice};
}
async function amend(t:Awaited<ReturnType<typeof fixture>>,baseId:string,price:number,discount?:number,tax?:number) {
 const order=await orders.create(t.company.id,t.user.id,{request_id:randomUUID(),base_estimate_id:baseId,title:`Change to ${price}`,reason:'Customer requested revised scope'});
 const line=await prisma.estimateLineItem.findFirstOrThrow({where:{estimateId:order.estimate_id}});
 await items.update(line.id,t.company.id,{unit_cost:price,...(tax!==undefined?{tax_rate:tax}:{})});
 if(discount!==undefined) await estimates.update(order.estimate_id,t.company.id,t.user.id,{discount_amount:discount});
 await approve(order.proposal_id,t.company.id,t.user.id);
 return orders.get(order.id,t.company.id);
}

describe('explicit approved contract amendments',()=>{
 it('bills only signed Decimal component deltas and preserves original invoice concessions',async()=>{
  const t=await fixture({tax:0.1,discount:10,concession:5});
  const change=await amend(t,t.estimate.id,150,20);
  expect(change.comparison).toMatchObject({base_total:100,new_total:145,change_amount:45,subtotal_delta:50,tax_delta:5,discount_delta:10});
  await expect(invoices.createFromEstimate(t.company.id,t.user.id,change.estimate_id,{})).rejects.toMatchObject({statusCode:409});
  const result=await orders.apply(change.id,t.company.id,t.user.id,randomUUID());
  expect(result.invoices).toHaveLength(1);expect(result.invoices[0]).toMatchObject({subtotal:50,tax_amount:5,discount_amount:10,total_amount:45,financial_basis_locked:true,root_invoice_id:t.invoice!.id});
  const original=await prisma.invoice.findUniqueOrThrow({where:{id:t.invoice!.id}});
  expect(Number(original.totalAmount)).toBe(95);expect(Number(original.amountPaid)).toBe(0);expect(original.financialBasisLocked).toBe(true);
  await expect(invoices.update(result.invoices[0].id,t.company.id,{discount_amount:1})).rejects.toMatchObject({statusCode:409});
  expect((await invoices.createFromEstimate(t.company.id,t.user.id,change.estimate_id,{})).id).toBe(result.invoices[0].id);
  expect(await prisma.invoice.count()).toBe(2);
 });
 it('records credits separately from partial cash and retains excess for later positive changes',async()=>{
  const t=await fixture();await invoices.send(t.invoice!.id,t.company.id,t.user.id);
  await finance.recordPayment(t.invoice!.id,t.company.id,t.user.id,{request_id:randomUUID(),amount:30,method:'cash'});
  const down=await amend(t,t.estimate.id,60);await orders.apply(down.id,t.company.id,t.user.id,randomUUID());
  let balance=await finance.getFinance(t.invoice!.id,t.company.id);
  expect(balance.invoice).toMatchObject({amount_paid:30,credit_amount:40,amount_due:30});expect(balance.payments).toHaveLength(1);
  const lower=await amend(t,down.estimate_id,20);const credit=await orders.apply(lower.id,t.company.id,t.user.id,randomUUID());
  expect(credit.credit_note).toMatchObject({amount:40,allocated_amount:30});
  balance=await finance.getFinance(t.invoice!.id,t.company.id);expect(balance.invoice).toMatchObject({amount_paid:30,credit_amount:70,amount_due:0,status:'paid'});
  const increase=await amend(t,lower.estimate_id,50);const billed=await orders.apply(increase.id,t.company.id,t.user.id,randomUUID());
  expect(billed.invoices[0]).toMatchObject({total_amount:30,amount_paid:0,credit_amount:10,amount_due:20});
  expect(await prisma.invoicePayment.count()).toBe(1);
 });
 it('serializes concurrent apply and request replay without duplicate invoices or notes',async()=>{
  const t=await fixture();const first=await amend(t,t.estimate.id,120);const second=await amend(t,first.estimate_id,140);
  const request=randomUUID();const results=await Promise.all([request,request,randomUUID()].map(key=>orders.apply(second.id,t.company.id,t.user.id,key)));
  expect(new Set(results.map(r=>r.invoices[0].id)).size).toBe(1);
  expect(await prisma.invoice.count()).toBe(3);expect(await prisma.creditNote.count()).toBe(0);
  expect((await orders.get(first.id,t.company.id)).status).toBe('applied');
  await expect(orders.apply(first.id,t.company.id,t.user.id,request)).rejects.toMatchObject({statusCode:409});
 });
 it('includes uninvoiced approved amendments in the first full invoice exactly once',async()=>{
  const t=await fixture({invoice:false});const change=await amend(t,t.estimate.id,140);
  await expect(orders.apply(change.id,t.company.id,t.user.id,randomUUID())).rejects.toMatchObject({statusCode:409});
  await expect(invoices.createFromEstimate(t.company.id,t.user.id,t.estimate.id,{})).rejects.toMatchObject({statusCode:409});
  const invoice=await invoices.createFromEstimate(t.company.id,t.user.id,change.estimate_id,{});
  expect(Number(invoice.totalAmount)).toBe(140);expect(invoice.financialBasisLocked).toBe(true);
  expect((await orders.get(change.id,t.company.id)).status).toBe('included');
  await orders.apply(change.id,t.company.id,t.user.id,randomUUID());expect(await prisma.invoice.count()).toBe(1);
 });
 it('reconciles available credit after a refund before exposing any renewed debt',async()=>{
  const t=await fixture();await invoices.send(t.invoice!.id,t.company.id,t.user.id);
  await finance.recordPayment(t.invoice!.id,t.company.id,t.user.id,{request_id:randomUUID(),amount:100,method:'cash'});
  const change=await amend(t,t.estimate.id,60);const applied=await orders.apply(change.id,t.company.id,t.user.id,randomUUID());
  expect(applied.credit_note).toMatchObject({amount:40,allocated_amount:0});
  await prisma.$transaction(async tx=>{
   const contract=await lockContractForInvoice(tx,t.invoice!.id,t.company.id);
   await tx.invoice.update({where:{id:t.invoice!.id},data:{amountPaid:60,amountDue:40,paymentReviewRequired:true}});
   await tx.invoicePayment.create({data:{invoiceId:t.invoice!.id,companyId:t.company.id,requestId:randomUUID(),amount:-40,method:'stripe_refund'}});
   await applyAvailableContractCredits(tx,t.company.id,contract.rootEstimateId!);
  });
  const result=await finance.getFinance(t.invoice!.id,t.company.id);
  expect(result.invoice).toMatchObject({amount_paid:60,credit_amount:40,amount_due:0,status:'paid'});expect(result.payments.map(p=>p.amount)).toEqual([100,-40]);
 });
 it('rejects stale, mismatched, unsigned and cross-tenant sources before a financial write',async()=>{
  const t=await fixture();const stranger=await prisma.company.create({data:{name:'Stranger'}});
  await expect(orders.create(stranger.id,t.user.id,{request_id:randomUUID(),base_estimate_id:t.estimate.id,title:'X',reason:'Y'})).rejects.toMatchObject({statusCode:404});
  const request={request_id:randomUUID(),base_estimate_id:t.estimate.id,title:'Add scope',reason:'Customer request'};
  const draft=await orders.create(t.company.id,t.user.id,request);
  expect((await orders.create(t.company.id,t.user.id,request)).id).toBe(draft.id);
  await expect(orders.create(t.company.id,t.user.id,{...request,title:'Changed'})).rejects.toMatchObject({statusCode:409});
  await expect(orders.apply(draft.id,t.company.id,t.user.id,randomUUID())).rejects.toMatchObject({statusCode:409});
  await approve(draft.proposal_id,t.company.id,t.user.id);
  await prisma.estimate.update({where:{id:draft.estimate_id},data:{totalAmount:999}});
  await expect(orders.apply(draft.id,t.company.id,t.user.id,randomUUID())).rejects.toMatchObject({statusCode:409});
  await expect(orders.get(draft.id,stranger.id)).rejects.toMatchObject({statusCode:404});
  expect(await prisma.invoice.count()).toBe(1);expect(await prisma.creditNote.count()).toBe(0);
 });
 it('refuses a manually repriced legacy root and a customer reassignment',async()=>{
  const t=await fixture();await prisma.invoice.update({where:{id:t.invoice!.id},data:{subtotal:150,totalAmount:150,amountDue:150,financialBasisLocked:false}});
  await expect(orders.create(t.company.id,t.user.id,{request_id:randomUUID(),base_estimate_id:t.estimate.id,title:'X',reason:'Y'})).rejects.toMatchObject({statusCode:409});
  const customer=await prisma.client.create({data:{companyId:t.company.id,name:'Other customer'}});
  await prisma.project.update({where:{id:t.project.id},data:{clientId:customer.id}});
  await prisma.invoice.delete({where:{id:t.invoice!.id}});
  await expect(invoices.createFromEstimate(t.company.id,t.user.id,t.estimate.id,{})).rejects.toMatchObject({statusCode:409});
 });
 it('applies a negative change once under concurrent requests and can replace requested changes',async()=>{
  const t=await fixture();const draft=await orders.create(t.company.id,t.user.id,{request_id:randomUUID(),base_estimate_id:t.estimate.id,title:'First change',reason:'Requested scope'});
  await proposals.send(draft.proposal_id,t.company.id,t.user.id);
  const sent=await proposals.getById(draft.proposal_id,t.company.id);
  await proposals.respondToProposal(sent.shareToken!,{decision:'changes_requested',message:'Please remove the new cabinet.'});
  expect((await orders.get(draft.id,t.company.id)).status).toBe('changes_requested');
  const replacement=await amend(t,t.estimate.id,60);
  const key=randomUUID();const results=await Promise.all([key,key,randomUUID()].map(request=>orders.apply(replacement.id,t.company.id,t.user.id,request)));
  expect(new Set(results.map(r=>r.credit_note!.id)).size).toBe(1);expect(await prisma.creditNote.count()).toBe(1);expect(await prisma.invoice.count()).toBe(1);
 });
 it('keeps issued notes and allocations immutable and blocks apply during active checkout',async()=>{
  const t=await fixture();const change=await amend(t,t.estimate.id,60);
  const attempt=await prisma.invoiceCheckoutAttempt.create({data:{invoiceId:t.invoice!.id,companyId:t.company.id,accountId:'acct_test',state:'OPEN',amount:100,currencyCode:'USD',paymentScope:'balance',integrationIdentifier:'test'}});
  await expect(orders.apply(change.id,t.company.id,t.user.id,randomUUID())).rejects.toMatchObject({statusCode:409});
  await prisma.invoiceCheckoutAttempt.update({where:{id:attempt.id},data:{state:'CANCELLED'}});
  await orders.apply(change.id,t.company.id,t.user.id,randomUUID());
  const note=await prisma.creditNote.findFirstOrThrow();const allocation=await prisma.creditAllocation.findFirstOrThrow();
  await expect(prisma.creditNote.update({where:{id:note.id},data:{amount:1000}})).rejects.toThrow();
  await expect(prisma.creditAllocation.update({where:{id:allocation.id},data:{amount:1}})).rejects.toThrow();
 });
});
