import { Request, Response } from 'express';
import { describe, expect, it, vi } from 'vitest';
import { ValidationError } from '../lib/errors';
import { createAssetSchema } from '../modules/assets/assets.validators';
import { appleSignInSchema, googleSignInSchema } from '../modules/auth/auth.validators';
import { batchCreateEstimateLineItemsSchema } from '../modules/estimate-line-items/estimate-line-items.validators';
import { updateMaterialSchema } from '../modules/materials/materials.validators';
import { staticMapQuerySchema } from '../modules/maps/maps.validators';
import { consumeUsageSchema } from '../modules/usage/usage.validators';
import { validate } from './validate.middleware';

describe('request validation compatibility', () => {
  it('keeps OAuth email optional and normalizes provided email', () => {
    for (const schema of [appleSignInSchema, googleSignInSchema]) {
      const required = { identity_token: 'identity', authorization_code: 'authorization' };
      expect(schema.safeParse(required).success).toBe(true);
      expect(schema.parse({ ...required, email: null }).email).toBeUndefined();
      expect(schema.parse({ ...required, email: 'USER@EXAMPLE.COM' }).email).toBe('user@example.com');
    }
  });

  it('retains explicit field error messages', () => {
    const missingMetric = consumeUsageSchema.safeParse({});
    const invalidMetric = consumeUsageSchema.safeParse({ metric_code: false });
    const missingSelection = updateMaterialSchema.safeParse({});
    const invalidAsset = createAssetSchema.safeParse({ url: '/image', asset_type: 'other' });

    expect(missingMetric.error?.issues[0].message).toBe('Metric code is required');
    expect(invalidMetric.error?.issues[0].message).toBe('Metric code must be AI_GENERATION or QUOTE_EXPORT');
    expect(missingSelection.error?.issues[0].message).toBe('is_selected is required');
    expect(invalidAsset.error?.issues[0].message).toBe('asset_type must be one of: original, ai_generated, document');
  });

  it('writes coerced query values and defaults back to the request', () => {
    const req = { query: { latitude: '30', longitude: '-97' } } as unknown as Request;
    const next = vi.fn();

    validate(staticMapQuerySchema, 'query')(req, {} as Response, next);

    expect(req.query).toEqual({
      latitude: 30, longitude: -97, zoom: 19, width: 640, height: 400,
      maptype: 'satellite', retina: true,
    });
    expect(next).toHaveBeenCalledExactlyOnceWith();
  });

  it('returns nested field errors through the existing API error contract', () => {
    const req = {
      body: { items: [{ category: 'materials', name: 'Item', quantity: 0, unit: 'each', unit_cost: 2 }] },
    } as Request;
    const next = vi.fn();

    validate(batchCreateEstimateLineItemsSchema)(req, {} as Response, next);

    const error = next.mock.calls[0][0] as ValidationError;
    expect(error).toBeInstanceOf(ValidationError);
    expect(error.statusCode).toBe(400);
    expect(error.fieldErrors).toEqual({ 'items.0.quantity': ['quantity must be positive'] });
  });

  it('rejects oversized batches before collecting per-item validation issues', () => {
    const result = batchCreateEstimateLineItemsSchema.safeParse({ items: Array(10_000).fill(null) });

    expect(result.success).toBe(false);
    expect(result.error?.issues).toEqual([
      expect.objectContaining({ path: ['items'], code: 'too_big', message: 'Maximum 200 line items per batch' }),
    ]);
  });
});
