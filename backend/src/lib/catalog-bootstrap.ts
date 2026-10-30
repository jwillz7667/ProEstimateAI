import { PlanCode, PrismaClient } from '@prisma/client';
import { PRO_PLAN_LIMITS, LEGACY_PREMIUM_PLAN_LIMITS } from './usage-limits';

/**
 * Create the production commerce catalog without importing the development
 * seed, which also creates demo companies, users, and customer records.
 * Existing catalog rows are authoritative and must survive redeploys/restores.
 */
export async function bootstrapCatalog(database: PrismaClient): Promise<void> {
  const freeFeatures = {
    CAN_GENERATE_PREVIEW: false,
    CAN_EXPORT_QUOTE: false,
    CAN_REMOVE_WATERMARK: false,
    CAN_USE_BRANDING: false,
    CAN_CREATE_INVOICE: false,
    CAN_SHARE_APPROVAL_LINK: false,
    CAN_EXPORT_MATERIAL_LINKS: false,
    CAN_USE_HIGH_RES_PREVIEW: false,
  };

  const proFeatures = {
    CAN_GENERATE_PREVIEW: true,
    CAN_EXPORT_QUOTE: true,
    CAN_REMOVE_WATERMARK: true,
    CAN_USE_BRANDING: true,
    CAN_CREATE_INVOICE: true,
    CAN_SHARE_APPROVAL_LINK: true,
    CAN_EXPORT_MATERIAL_LINKS: true,
    CAN_USE_HIGH_RES_PREVIEW: true,
    LIMITS: PRO_PLAN_LIMITS,
  };

  await database.$transaction(async (transaction) => {
    // Empty-update upserts can race when replicas start on an empty database.
    // Serialize this catalog bootstrap per schema until the transaction ends.
    await transaction.$queryRaw`
      SELECT pg_advisory_xact_lock(
        hashtext(current_schema()), hashtext('proestimate:catalog-bootstrap')
      )::text
    `;

    await transaction.plan.upsert({
      where: { code: PlanCode.FREE_STARTER },
      update: {},
      create: {
        code: PlanCode.FREE_STARTER,
        displayName: 'Free',
        description: 'Manual estimating only. AI features require a subscription.',
        featuresJson: freeFeatures,
      },
    });

    const monthlyPlan = await transaction.plan.upsert({
      where: { code: PlanCode.PRO_MONTHLY },
      update: {},
      create: {
        code: PlanCode.PRO_MONTHLY,
        displayName: 'Pro Monthly',
        description: 'Unlimited AI within fair-use caps, branding, and invoicing',
        featuresJson: proFeatures,
      },
    });

    const annualPlan = await transaction.plan.upsert({
      where: { code: PlanCode.PRO_ANNUAL },
      update: {},
      create: {
        code: PlanCode.PRO_ANNUAL,
        displayName: 'Pro Annual',
        description: 'Everything in Pro Monthly — save 17%',
        featuresJson: proFeatures,
      },
    });

    await transaction.subscriptionProduct.upsert({
      where: { storeProductId: 'proestimate.pro.monthly' },
      update: {},
      create: {
        planId: monthlyPlan.id,
        storeProductId: 'proestimate.pro.monthly',
        displayName: 'Pro Monthly',
        description: 'Unlimited AI generations, invoicing, and branding',
        priceDisplay: '$19.99/mo',
        billingPeriodLabel: 'month',
        hasIntroOffer: true,
        introOfferDisplayText: '7-day free trial',
        isFeatured: true,
        sortOrder: 1,
      },
    });

    await transaction.subscriptionProduct.upsert({
      where: { storeProductId: 'proestimate.pro.annual' },
      update: {},
      create: {
        planId: annualPlan.id,
        storeProductId: 'proestimate.pro.annual',
        displayName: 'Pro Annual',
        description: 'Everything in Pro — save 17%',
        priceDisplay: '$199.99/yr',
        billingPeriodLabel: 'year',
        hasIntroOffer: false,
        isFeatured: false,
        savingsText: 'Save 17%',
        sortOrder: 2,
      },
    });

    // These historical SKUs remain resolvable for signed restores/renewals on a
    // fresh database. They stay retired from sale and purchase-attempt creation.
    const premiumFeatures = {
      ...proFeatures,
      CAN_USE_PRIORITY_GENERATION: true,
      LIMITS: LEGACY_PREMIUM_PLAN_LIMITS,
    };
    const legacyPremiumPlans = [
      { code: PlanCode.PREMIUM_MONTHLY, name: 'Premium Monthly', period: 'month',
        productId: 'proestimate.premium.monthly', price: '$49.99/mo', sortOrder: 3 },
      { code: PlanCode.PREMIUM_ANNUAL, name: 'Premium Annual', period: 'year',
        productId: 'proestimate.premium.annual', price: '$499.99/yr', sortOrder: 4 },
    ];
    for (const legacy of legacyPremiumPlans) {
      const plan = await transaction.plan.upsert({
        where: { code: legacy.code },
        update: {},
        create: {
          code: legacy.code,
          displayName: legacy.name,
          description: 'Legacy Premium subscription; existing purchases only',
          featuresJson: premiumFeatures,
          isActive: false,
        },
      });
      await transaction.subscriptionProduct.upsert({
        where: { storeProductId: legacy.productId },
        update: {},
        create: {
          planId: plan.id,
          storeProductId: legacy.productId,
          displayName: legacy.name,
          description: 'Legacy Premium subscription; existing purchases only',
          priceDisplay: legacy.price,
          billingPeriodLabel: legacy.period,
          hasIntroOffer: false,
          isFeatured: false,
          sortOrder: legacy.sortOrder,
        },
      });
    }
  }, { maxWait: 10_000, timeout: 30_000 });
}
