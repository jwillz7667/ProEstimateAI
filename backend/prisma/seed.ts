import { PrismaClient, PlanCode, UsageMetricCode } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  // Plans
  const freePlan = await prisma.plan.upsert({
    where: { code: PlanCode.FREE_STARTER },
    update: {},
    create: {
      code: PlanCode.FREE_STARTER,
      displayName: 'Free Starter',
      description: 'Get started with 3 AI generations and 3 quote exports',
      featuresJson: {
        CAN_GENERATE_PREVIEW: 'CREDIT_GATED',
        CAN_EXPORT_QUOTE: 'CREDIT_GATED',
        CAN_REMOVE_WATERMARK: false,
        CAN_USE_BRANDING: false,
        CAN_CREATE_INVOICE: false,
        CAN_SHARE_APPROVAL_LINK: false,
        CAN_EXPORT_MATERIAL_LINKS: false,
        CAN_USE_HIGH_RES_PREVIEW: false,
      },
    },
  });

  const proMonthlyPlan = await prisma.plan.upsert({
    where: { code: PlanCode.PRO_MONTHLY },
    update: {},
    create: {
      code: PlanCode.PRO_MONTHLY,
      displayName: 'Pro Monthly',
      description: 'Unlimited AI generations, invoicing, and branding',
      featuresJson: {
        CAN_GENERATE_PREVIEW: true,
        CAN_EXPORT_QUOTE: true,
        CAN_REMOVE_WATERMARK: true,
        CAN_USE_BRANDING: true,
        CAN_CREATE_INVOICE: true,
        CAN_SHARE_APPROVAL_LINK: true,
        CAN_EXPORT_MATERIAL_LINKS: true,
        CAN_USE_HIGH_RES_PREVIEW: true,
      },
    },
  });

  const proAnnualPlan = await prisma.plan.upsert({
    where: { code: PlanCode.PRO_ANNUAL },
    update: {},
    create: {
      code: PlanCode.PRO_ANNUAL,
      displayName: 'Pro Annual',
      description: 'Everything in Pro Monthly — save 30%',
      featuresJson: {
        CAN_GENERATE_PREVIEW: true,
        CAN_EXPORT_QUOTE: true,
        CAN_REMOVE_WATERMARK: true,
        CAN_USE_BRANDING: true,
        CAN_CREATE_INVOICE: true,
        CAN_SHARE_APPROVAL_LINK: true,
        CAN_EXPORT_MATERIAL_LINKS: true,
        CAN_USE_HIGH_RES_PREVIEW: true,
      },
    },
  });

  // Subscription Products
  await prisma.subscriptionProduct.upsert({
    where: { storeProductId: 'proestimate.pro.monthly' },
    update: {},
    create: {
      planId: proMonthlyPlan.id,
      storeProductId: 'proestimate.pro.monthly',
      displayName: 'Pro Monthly',
      description: 'Unlimited AI generations, invoicing, and branding',
      priceDisplay: '$29.99/mo',
      billingPeriodLabel: 'month',
      hasIntroOffer: true,
      introOfferDisplayText: '7-day free trial',
      isFeatured: true,
      sortOrder: 1,
    },
  });

  await prisma.subscriptionProduct.upsert({
    where: { storeProductId: 'proestimate.pro.annual' },
    update: {},
    create: {
      planId: proAnnualPlan.id,
      storeProductId: 'proestimate.pro.annual',
      displayName: 'Pro Annual',
      description: 'Everything in Pro — save 30%',
      priceDisplay: '$249.99/yr',
      billingPeriodLabel: 'year',
      hasIntroOffer: false,
      isFeatured: false,
      savingsText: 'Save 30%',
      sortOrder: 2,
    },
  });

  // Demo Company
  const company = await prisma.company.upsert({
    where: { id: 'demo-company-001' },
    update: {},
    create: {
      id: 'demo-company-001',
      name: 'Apex Remodeling Co.',
      phone: '(555) 234-5678',
      email: 'info@apexremodeling.com',
      address: '742 Contractor Blvd',
      city: 'Austin',
      state: 'TX',
      zip: '78701',
      primaryColor: '#F97316',
      estimatePrefix: 'APX',
      invoicePrefix: 'APX-INV',
      defaultTaxRate: 0.0825,
      defaultMarkupPercent: 20,
    },
  });

  // Demo User
  const passwordHash = await bcrypt.hash('demo1234', 12);
  const user = await prisma.user.upsert({
    where: { email: 'mike@apexremodeling.com' },
    update: {},
    create: {
      id: 'demo-user-001',
      companyId: company.id,
      email: 'mike@apexremodeling.com',
      passwordHash,
      fullName: 'Mike Johnson',
      role: 'OWNER',
      phone: '(555) 234-5678',
    },
  });

  // User Entitlement (FREE)
  await prisma.userEntitlement.upsert({
    where: { userId: user.id },
    update: {},
    create: {
      userId: user.id,
      companyId: company.id,
      planId: freePlan.id,
      status: 'FREE',
    },
  });

  // Usage Buckets
  await prisma.usageBucket.upsert({
    where: { userId_metricCode: { userId: user.id, metricCode: UsageMetricCode.AI_GENERATION } },
    update: {},
    create: {
      userId: user.id,
      companyId: company.id,
      metricCode: UsageMetricCode.AI_GENERATION,
      includedQuantity: 3,
      consumedQuantity: 0,
      source: 'STARTER_CREDITS',
    },
  });

  await prisma.usageBucket.upsert({
    where: { userId_metricCode: { userId: user.id, metricCode: UsageMetricCode.QUOTE_EXPORT } },
    update: {},
    create: {
      userId: user.id,
      companyId: company.id,
      metricCode: UsageMetricCode.QUOTE_EXPORT,
      includedQuantity: 3,
      consumedQuantity: 0,
      source: 'STARTER_CREDITS',
    },
  });

  // Sample Clients
  const clientNames = [
    { name: 'Sarah Thompson', email: 'sarah@example.com', phone: '(555) 111-2222', address: '123 Oak Lane', city: 'Austin', state: 'TX', zip: '78702' },
    { name: 'James Rivera', email: 'james@example.com', phone: '(555) 333-4444', address: '456 Pine St', city: 'Austin', state: 'TX', zip: '78703' },
    { name: 'Emily Chen', email: 'emily@example.com', phone: '(555) 555-6666', address: '789 Elm Ave', city: 'Round Rock', state: 'TX', zip: '78664' },
    { name: 'David Martinez', email: 'david@example.com', phone: '(555) 777-8888', address: '321 Cedar Dr', city: 'Georgetown', state: 'TX', zip: '78626' },
    { name: 'Lisa Anderson', email: 'lisa@example.com', phone: '(555) 999-0000', address: '654 Birch Ct', city: 'Pflugerville', state: 'TX', zip: '78660' },
  ];

  const clients = [];
  for (const c of clientNames) {
    const client = await prisma.client.create({
      data: { companyId: company.id, ...c },
    });
    clients.push(client);
  }

  // Sample Projects
  const projectData = [
    { clientId: clients[0].id, title: 'Thompson Kitchen Remodel', projectType: 'KITCHEN' as const, status: 'DRAFT' as const, qualityTier: 'PREMIUM' as const, budgetMin: 25000, budgetMax: 45000, squareFootage: 180 },
    { clientId: clients[1].id, title: 'Rivera Master Bath', projectType: 'BATHROOM' as const, status: 'ESTIMATE_CREATED' as const, qualityTier: 'LUXURY' as const, budgetMin: 15000, budgetMax: 30000, squareFootage: 120 },
    { clientId: clients[2].id, title: 'Chen Living Room Flooring', projectType: 'FLOORING' as const, status: 'PROPOSAL_SENT' as const, qualityTier: 'STANDARD' as const, budgetMin: 8000, budgetMax: 15000, squareFootage: 350 },
    { clientId: clients[3].id, title: 'Martinez Exterior Paint', projectType: 'PAINTING' as const, status: 'APPROVED' as const, qualityTier: 'PREMIUM' as const, budgetMin: 5000, budgetMax: 10000 },
    { clientId: clients[4].id, title: 'Anderson Roof Replacement', projectType: 'ROOFING' as const, status: 'COMPLETED' as const, qualityTier: 'STANDARD' as const, budgetMin: 12000, budgetMax: 20000 },
  ];

  for (const p of projectData) {
    await prisma.project.create({
      data: { companyId: company.id, ...p },
    });
  }

  // Sample Pricing Profile
  const profile = await prisma.pricingProfile.create({
    data: {
      companyId: company.id,
      name: 'Standard Residential',
      defaultMarkupPercent: 20,
      contingencyPercent: 10,
      wasteFactor: 5,
      isDefault: true,
    },
  });

  // Sample Labor Rate Rule
  await prisma.laborRateRule.create({
    data: {
      pricingProfileId: profile.id,
      category: 'General Labor',
      ratePerHour: 65,
      minimumHours: 2,
    },
  });

  console.log('Seed completed successfully');
}

main()
  .catch((e) => {
    console.error('Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
