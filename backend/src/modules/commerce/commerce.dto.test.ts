import { UsageBucket } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { deriveFeatureFlags, FeatureFlagsDto } from "./commerce.dto";
import { PlanCode, UsageMetricCode } from "../../types/enums";

function makeBucket(
  metricCode: UsageMetricCode,
  included: number,
  consumed: number,
): UsageBucket {
  return {
    id: `bucket_${metricCode}`,
    userId: "user_1",
    companyId: "company_1",
    metricCode,
    includedQuantity: included,
    consumedQuantity: consumed,
    resetPolicy: "NEVER",
    periodStart: null,
    periodEnd: null,
    source: "STARTER_CREDITS",
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}

const ALL_UNLOCKED: FeatureFlagsDto = {
  CAN_GENERATE_PREVIEW: true,
  CAN_EXPORT_QUOTE: true,
  CAN_REMOVE_WATERMARK: true,
  CAN_USE_BRANDING: true,
  CAN_CREATE_INVOICE: true,
  CAN_SHARE_APPROVAL_LINK: true,
  CAN_EXPORT_MATERIAL_LINKS: true,
  CAN_USE_HIGH_RES_PREVIEW: true,
};

const PAID_PLANS: PlanCode[] = [
  "PRO_MONTHLY",
  "PRO_ANNUAL",
  "PREMIUM_MONTHLY",
  "PREMIUM_ANNUAL",
];

describe("deriveFeatureFlags", () => {
  it.each(PAID_PLANS)(
    "unlocks every feature for %s regardless of usage buckets",
    (plan) => {
      // Pass empty buckets to prove paid plans never depend on credit balance.
      expect(deriveFeatureFlags(plan, [])).toEqual(ALL_UNLOCKED);
    },
  );

  it("treats Premium identically to Pro (regression: Premium must not get the Free feature set)", () => {
    const pro = deriveFeatureFlags("PRO_MONTHLY", []);
    expect(deriveFeatureFlags("PREMIUM_MONTHLY", [])).toEqual(pro);
    expect(deriveFeatureFlags("PREMIUM_ANNUAL", [])).toEqual(pro);
  });

  it("grants credit-gated features to Free when starter credits remain", () => {
    const buckets = [
      makeBucket("AI_GENERATION", 3, 1),
      makeBucket("QUOTE_EXPORT", 3, 0),
    ];

    const flags = deriveFeatureFlags("FREE_STARTER", buckets);

    expect(flags.CAN_GENERATE_PREVIEW).toBe(true);
    expect(flags.CAN_EXPORT_QUOTE).toBe(true);
    expect(flags.CAN_REMOVE_WATERMARK).toBe(false);
    expect(flags.CAN_USE_BRANDING).toBe(false);
    expect(flags.CAN_CREATE_INVOICE).toBe(false);
    expect(flags.CAN_SHARE_APPROVAL_LINK).toBe(false);
    expect(flags.CAN_EXPORT_MATERIAL_LINKS).toBe(false);
    expect(flags.CAN_USE_HIGH_RES_PREVIEW).toBe(false);
  });

  it("denies credit-gated features to Free when starter credits are exhausted", () => {
    const buckets = [
      makeBucket("AI_GENERATION", 3, 3),
      makeBucket("QUOTE_EXPORT", 3, 5),
    ];

    const flags = deriveFeatureFlags("FREE_STARTER", buckets);

    expect(flags.CAN_GENERATE_PREVIEW).toBe(false);
    expect(flags.CAN_EXPORT_QUOTE).toBe(false);
  });

  it("denies all features to Free when no usage buckets exist", () => {
    const flags = deriveFeatureFlags("FREE_STARTER", []);

    expect(Object.values(flags).every((v) => v === false)).toBe(true);
  });
});
