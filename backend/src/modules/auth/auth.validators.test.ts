import { describe, expect, it } from 'vitest';
import { resetPasswordSchema, signupSchema } from './auth.validators';
describe('bcrypt password boundary', () => {
  for (const password of ['Aa1' + 'x'.repeat(70), 'Aa1' + '💡'.repeat(18)]) {
    it(`rejects passwords whose UTF-8 encoding exceeds bcrypt's 72-byte limit (${Buffer.byteLength(password)} bytes)`, () => {
      expect(signupSchema.safeParse({ full_name: 'Test User', email: 'test@example.test', company_name: 'Test Co', password }).success).toBe(false);
      expect(resetPasswordSchema.safeParse({ token: 'reset', new_password: password }).success).toBe(false);
    });
  }
  it('accepts a complete 72-byte password', () => {
    expect(resetPasswordSchema.safeParse({ token: 'reset', new_password: 'Aa1' + 'x'.repeat(69) }).success).toBe(true);
  });
});
