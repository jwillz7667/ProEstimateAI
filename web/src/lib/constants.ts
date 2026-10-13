/**
 * Shared marketing-site constants.
 *
 * Centralized so a single edit updates the App Store URL, support
 * email, and external links everywhere on the site.
 */


export const APP_STORE_URL =
  "https://apps.apple.com/app/proestimate-ai/id6762563132";

export const SUPPORT_EMAIL = "support@proestimateai.com";
export const SITE_URL = "https://proestimateai.com";

export const PRICING = {
  proMonthly: {
    price: "$19.99",
    cadence: "/month",
    trial: "7-day free trial",
  },
} as const;
