import { ValidationError } from '../../lib/errors';

/**
 * Our supported onboarding subset, not a guarantee of platform/account
 * eligibility. Stripe still validates the platform and requested capability.
 * Native Stripe availability (preview/extended-network excluded): https://stripe.com/global
 * Platform restrictions: https://docs.stripe.com/connect/how-connect-works#availability
 */
export const SUPPORTED_MERCHANT_COUNTRIES = [
  'AE', 'AT', 'AU', 'BE', 'BG', 'BR', 'CA', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR',
  'GB', 'GI', 'GR', 'HK', 'HU', 'HR', 'IE', 'IT', 'JP', 'LI', 'LT', 'LU', 'LV', 'MT', 'MX', 'MY',
  'NL', 'NO', 'NZ', 'PL', 'PT', 'RO', 'SE', 'SG', 'SI', 'SK', 'TH', 'US',
] as const;
const supportedCountries = new Set<string>(SUPPORTED_MERCHANT_COUNTRIES);

export function normalizedMerchantCountry(country: string) {
  const normalized = country.toUpperCase();
  if (!/^[A-Z]{2}$/.test(normalized)) throw new ValidationError('Choose your business country.');
  return normalized;
}

export function requireSupportedMerchantCountry(country: string) {
  if (!supportedCountries.has(country)) {
    throw new ValidationError('Choose your actual business country from the available payment setup countries. Stripe eligibility also depends on your business and the platform. Contact support if your country is not available.', { country: ['This business country is not currently supported.'] });
  }
}

/** Only a provider rejection of account CREATE may release its reservation. */
export class MerchantCountryRejectedError extends ValidationError {
  constructor() {
    super('Stripe could not create a payment account for this business country. Refresh and select your correct business country, or contact support if payment setup is unavailable there.', { country: ['Stripe rejected payment account creation for this country.'] });
    this.name = 'MerchantCountryRejectedError';
  }
}
