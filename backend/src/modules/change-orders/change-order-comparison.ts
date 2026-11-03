import { ChangeOrder, Estimate, Prisma } from '@prisma/client';
import { z } from 'zod';
import { ConflictError } from '../../lib/errors';

const money=z.number().finite();
export const changeOrderBaseSchema=z.object({estimate_id:z.string(),estimate_number:z.string(),version:z.number().int(),document_hash:z.string(),subtotal:z.string(),tax:z.string(),discount:z.string(),total:z.string(),scope:z.object({line_items:z.array(z.object({name:z.string(),description:z.string().nullable(),quantity:money,unit:z.string(),line_total:money})),assumptions:z.string().nullable(),exclusions:z.string().nullable()})});
export const changeOrderComparisonSchema=z.object({id:z.string(),title:z.string(),reason:z.string(),currency_code:z.literal('USD'),base_estimate_number:z.string(),base_version:z.number().int(),base_document_hash:z.string(),base_total:money,new_total:money,change_amount:money,subtotal_delta:money,tax_delta:money,discount_delta:money,base_scope:changeOrderBaseSchema.shape.scope,billing_effect:z.enum(['additional_invoice','credit_note','included_in_first_invoice','no_price_change'])});
export type ChangeOrderComparison=z.infer<typeof changeOrderComparisonSchema>;
export function readChangeOrderBase(value:unknown) {
 const parsed=changeOrderBaseSchema.safeParse(value);
 if(!parsed.success) throw new ConflictError('The saved change order baseline needs review.');
 return parsed.data;
}
export function toChangeOrderComparison(changeOrder:ChangeOrder,estimate:Estimate):ChangeOrderComparison {
 const base=readChangeOrderBase(changeOrder.baseSnapshot);
 const subtotal=estimate.subtotalMaterials.plus(estimate.subtotalLabor).plus(estimate.subtotalOther);
 const delta=estimate.totalAmount.minus(base.total).toDecimalPlaces(2);
 return {id:changeOrder.id,title:changeOrder.title,reason:changeOrder.reason,currency_code:'USD',base_estimate_number:base.estimate_number,base_version:base.version,base_document_hash:base.document_hash,base_total:Number(base.total),new_total:Number(estimate.totalAmount),change_amount:Number(delta),subtotal_delta:Number(subtotal.minus(base.subtotal)),tax_delta:Number(estimate.taxAmount.minus(base.tax)),discount_delta:Number(estimate.discountAmount.minus(base.discount)),base_scope:base.scope,billing_effect:!changeOrder.rootInvoiceId?'included_in_first_invoice':delta.gt(0)?'additional_invoice':delta.lt(0)?'credit_note':'no_price_change'};
}
/** Decimal arithmetic is reconstructed from frozen decimal strings, never a
 * subtraction of binary floating point public DTO values.
 */
export function changeOrderDeltas(changeOrder:ChangeOrder,estimate:Estimate) {
 const base=readChangeOrderBase(changeOrder.baseSnapshot);
 return {subtotal:estimate.subtotalMaterials.plus(estimate.subtotalLabor).plus(estimate.subtotalOther).minus(base.subtotal),tax:estimate.taxAmount.minus(base.tax),discount:estimate.discountAmount.minus(base.discount),total:estimate.totalAmount.minus(base.total)};
}
