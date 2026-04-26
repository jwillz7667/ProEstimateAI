import {
  PrismaClient,
  PlanCode,
  UsageMetricCode,
  ProjectType,
  ProjectStatus,
  QualityTier,
  EstimateStatus,
  ProposalStatus,
  InvoiceStatus,
  LineItemCategory,
  GenerationStatus,
  ActivityAction,
  EntitlementStatus,
  UserRole,
} from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function daysAgo(n: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d;
}

function daysFromNow(n: number): Date {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d;
}

function randomBetween(min: number, max: number): number {
  return Math.round((Math.random() * (max - min) + min) * 100) / 100;
}

// ---------------------------------------------------------------------------
// Main seed
// ---------------------------------------------------------------------------

async function main() {
  console.log('🌱 Seeding database...\n');

  // =========================================================================
  // 1. PLANS & SUBSCRIPTION PRODUCTS
  // =========================================================================
  console.log('  Plans & products...');

  // Per-plan AI/export caps. Stored under featuresJson.LIMITS and enforced by
  // backend/src/modules/commerce/entitlement-gate.ts via rolling-window checks.
  const proLimits = {
    AI_GENERATION: { daily: 20, weekly: 75,  monthly: 200 },
    QUOTE_EXPORT:  { daily: 30, weekly: 150, monthly: 400 },
  };

  const freePlanFeatures = {
    CAN_GENERATE_PREVIEW: false,
    CAN_EXPORT_QUOTE: false,
    CAN_REMOVE_WATERMARK: false,
    CAN_USE_BRANDING: false,
    CAN_CREATE_INVOICE: false,
    CAN_SHARE_APPROVAL_LINK: false,
    CAN_EXPORT_MATERIAL_LINKS: false,
    CAN_USE_HIGH_RES_PREVIEW: false,
  };

  const proPlanFeatures = {
    CAN_GENERATE_PREVIEW: true,
    CAN_EXPORT_QUOTE: true,
    CAN_REMOVE_WATERMARK: true,
    CAN_USE_BRANDING: true,
    CAN_CREATE_INVOICE: true,
    CAN_SHARE_APPROVAL_LINK: true,
    CAN_EXPORT_MATERIAL_LINKS: true,
    CAN_USE_HIGH_RES_PREVIEW: true,
    LIMITS: proLimits,
  };

  const freePlan = await prisma.plan.upsert({
    where: { code: PlanCode.FREE_STARTER },
    update: { featuresJson: freePlanFeatures },
    create: {
      code: PlanCode.FREE_STARTER,
      displayName: 'Free',
      description: 'Manual estimating only. AI features require a subscription.',
      featuresJson: freePlanFeatures,
    },
  });

  const proMonthlyPlan = await prisma.plan.upsert({
    where: { code: PlanCode.PRO_MONTHLY },
    update: { featuresJson: proPlanFeatures },
    create: {
      code: PlanCode.PRO_MONTHLY,
      displayName: 'Pro Monthly',
      description: 'Unlimited AI within fair-use caps, branding, and invoicing',
      featuresJson: proPlanFeatures,
    },
  });

  const proAnnualPlan = await prisma.plan.upsert({
    where: { code: PlanCode.PRO_ANNUAL },
    update: { featuresJson: proPlanFeatures },
    create: {
      code: PlanCode.PRO_ANNUAL,
      displayName: 'Pro Annual',
      description: 'Everything in Pro Monthly — save 17%',
      featuresJson: proPlanFeatures,
    },
  });

  await prisma.subscriptionProduct.upsert({
    where: { storeProductId: 'proestimate.pro.monthly' },
    update: {},
    create: {
      planId: proMonthlyPlan.id,
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

  await prisma.subscriptionProduct.upsert({
    where: { storeProductId: 'proestimate.pro.annual' },
    update: {},
    create: {
      planId: proAnnualPlan.id,
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

  // =========================================================================
  // 2. COMPANIES
  // =========================================================================
  console.log('  Companies...');

  const passwordHash = await bcrypt.hash('demo1234', 12);

  const companyA = await prisma.company.upsert({
    where: { id: 'seed-company-apex' },
    update: {},
    create: {
      id: 'seed-company-apex',
      name: 'Apex Remodeling Co.',
      phone: '(512) 555-0100',
      email: 'info@apexremodeling.com',
      address: '742 Contractor Blvd',
      city: 'Austin',
      state: 'TX',
      zip: '78701',
      primaryColor: '#FF9230',
      secondaryColor: '#1E293B',
      estimatePrefix: 'APX',
      invoicePrefix: 'APX-INV',
      proposalPrefix: 'APX-PROP',
      defaultTaxRate: 0.0825,
      defaultMarkupPercent: 15,
      nextEstimateNumber: 1001,
      nextInvoiceNumber: 2001,
      nextProposalNumber: 3001,
      defaultLanguage: 'en',
      timezone: 'America/Chicago',
      websiteUrl: 'https://apexremodeling.com',
      taxLabel: 'Sales Tax',
    },
  });

  const companyB = await prisma.company.upsert({
    where: { id: 'seed-company-summit' },
    update: {},
    create: {
      id: 'seed-company-summit',
      name: 'Summit Home Solutions',
      phone: '(720) 555-0200',
      email: 'hello@summithome.co',
      address: '1800 Market St, Suite 210',
      city: 'Denver',
      state: 'CO',
      zip: '80202',
      primaryColor: '#FF9230',
      secondaryColor: '#334155',
      estimatePrefix: 'SHS',
      invoicePrefix: 'SHS-INV',
      proposalPrefix: 'SHS-PROP',
      defaultTaxRate: 0.029,
      defaultMarkupPercent: 20,
      nextEstimateNumber: 5001,
      nextInvoiceNumber: 6001,
      nextProposalNumber: 7001,
      defaultLanguage: 'en',
      timezone: 'America/Denver',
      websiteUrl: 'https://summithomesolutions.com',
      taxLabel: 'CO Sales Tax',
    },
  });

  // =========================================================================
  // 3. USERS
  // =========================================================================
  console.log('  Users...');

  // Company A — Apex
  const mike = await prisma.user.upsert({
    where: { email: 'mike@apexremodeling.com' },
    update: {},
    create: {
      id: 'seed-user-mike',
      companyId: companyA.id,
      email: 'mike@apexremodeling.com',
      passwordHash,
      fullName: 'Mike Johnson',
      role: UserRole.OWNER,
      phone: '(512) 555-0101',
    },
  });

  const jessica = await prisma.user.upsert({
    where: { email: 'jessica@apexremodeling.com' },
    update: {},
    create: {
      id: 'seed-user-jessica',
      companyId: companyA.id,
      email: 'jessica@apexremodeling.com',
      passwordHash,
      fullName: 'Jessica Reyes',
      role: UserRole.ESTIMATOR,
      phone: '(512) 555-0102',
    },
  });

  const tom = await prisma.user.upsert({
    where: { email: 'tom@apexremodeling.com' },
    update: {},
    create: {
      id: 'seed-user-tom',
      companyId: companyA.id,
      email: 'tom@apexremodeling.com',
      passwordHash,
      fullName: 'Tom Bradley',
      role: UserRole.VIEWER,
      phone: '(512) 555-0103',
    },
  });

  // Company B — Summit
  const rachel = await prisma.user.upsert({
    where: { email: 'rachel@summithome.co' },
    update: {},
    create: {
      id: 'seed-user-rachel',
      companyId: companyB.id,
      email: 'rachel@summithome.co',
      passwordHash,
      fullName: 'Rachel Kim',
      role: UserRole.OWNER,
      phone: '(720) 555-0201',
    },
  });

  const derek = await prisma.user.upsert({
    where: { email: 'derek@summithome.co' },
    update: {},
    create: {
      id: 'seed-user-derek',
      companyId: companyB.id,
      email: 'derek@summithome.co',
      passwordHash,
      fullName: 'Derek Patel',
      role: UserRole.ADMIN,
      phone: '(720) 555-0202',
    },
  });

  // =========================================================================
  // 4. ENTITLEMENTS & USAGE BUCKETS
  // =========================================================================
  console.log('  Entitlements & usage...');

  // Mike — Pro Monthly (active subscriber)
  await prisma.userEntitlement.upsert({
    where: { userId: mike.id },
    update: {},
    create: {
      userId: mike.id,
      companyId: companyA.id,
      planId: proMonthlyPlan.id,
      status: EntitlementStatus.PRO_ACTIVE,
      storeProductId: 'proestimate.pro.monthly',
      originalTransactionId: 'seed-txn-001',
      latestTransactionId: 'seed-txn-001',
      renewalDate: daysFromNow(22),
      startsAt: daysAgo(8),
      isAutoRenewEnabled: true,
      source: 'APP_STORE',
      environment: 'Sandbox',
    },
  });

  // Jessica — Free
  await prisma.userEntitlement.upsert({
    where: { userId: jessica.id },
    update: {},
    create: {
      userId: jessica.id,
      companyId: companyA.id,
      planId: freePlan.id,
      status: EntitlementStatus.FREE,
    },
  });

  // Tom — Free
  await prisma.userEntitlement.upsert({
    where: { userId: tom.id },
    update: {},
    create: {
      userId: tom.id,
      companyId: companyA.id,
      planId: freePlan.id,
      status: EntitlementStatus.FREE,
    },
  });

  // Rachel — Pro Annual
  await prisma.userEntitlement.upsert({
    where: { userId: rachel.id },
    update: {},
    create: {
      userId: rachel.id,
      companyId: companyB.id,
      planId: proAnnualPlan.id,
      status: EntitlementStatus.PRO_ACTIVE,
      storeProductId: 'proestimate.pro.annual',
      originalTransactionId: 'seed-txn-002',
      latestTransactionId: 'seed-txn-002',
      renewalDate: daysFromNow(290),
      startsAt: daysAgo(75),
      isAutoRenewEnabled: true,
      source: 'APP_STORE',
      environment: 'Sandbox',
    },
  });

  // Derek — Trial Active
  await prisma.userEntitlement.upsert({
    where: { userId: derek.id },
    update: {},
    create: {
      userId: derek.id,
      companyId: companyB.id,
      planId: proMonthlyPlan.id,
      status: EntitlementStatus.TRIAL_ACTIVE,
      storeProductId: 'proestimate.pro.monthly',
      trialEndsAt: daysFromNow(4),
      startsAt: daysAgo(3),
      isAutoRenewEnabled: true,
      source: 'APP_STORE',
      environment: 'Sandbox',
    },
  });

  // Usage buckets for free users
  for (const u of [jessica, tom]) {
    for (const metric of [UsageMetricCode.AI_GENERATION, UsageMetricCode.QUOTE_EXPORT]) {
      await prisma.usageBucket.upsert({
        where: {
          userId_companyId_metricCode_source: {
            userId: u.id,
            companyId: companyA.id,
            metricCode: metric,
            source: 'STARTER_CREDITS',
          },
        },
        update: {},
        create: {
          userId: u.id,
          companyId: companyA.id,
          metricCode: metric,
          includedQuantity: 3,
          consumedQuantity: metric === UsageMetricCode.AI_GENERATION ? 1 : 0,
          source: 'STARTER_CREDITS',
        },
      });
    }
  }

  // Subscription events
  await prisma.subscriptionEvent.create({
    data: {
      entitlementId: (await prisma.userEntitlement.findUnique({ where: { userId: mike.id } }))!.id,
      userId: mike.id,
      companyId: companyA.id,
      eventType: 'INITIAL_PURCHASE',
      storeProductId: 'proestimate.pro.monthly',
      transactionId: 'seed-txn-001',
      environment: 'Sandbox',
      platform: 'ios',
      effectiveAt: daysAgo(8),
    },
  });

  await prisma.subscriptionEvent.create({
    data: {
      entitlementId: (await prisma.userEntitlement.findUnique({ where: { userId: rachel.id } }))!.id,
      userId: rachel.id,
      companyId: companyB.id,
      eventType: 'INITIAL_PURCHASE',
      storeProductId: 'proestimate.pro.annual',
      transactionId: 'seed-txn-002',
      environment: 'Sandbox',
      platform: 'ios',
      effectiveAt: daysAgo(75),
    },
  });

  await prisma.subscriptionEvent.create({
    data: {
      entitlementId: (await prisma.userEntitlement.findUnique({ where: { userId: derek.id } }))!.id,
      userId: derek.id,
      companyId: companyB.id,
      eventType: 'TRIAL_STARTED',
      storeProductId: 'proestimate.pro.monthly',
      environment: 'Sandbox',
      platform: 'ios',
      effectiveAt: daysAgo(3),
    },
  });

  // =========================================================================
  // 5. CLIENTS
  // =========================================================================
  console.log('  Clients...');

  // Company A clients
  const clientsA = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'Sarah Thompson',
        email: 'sarah.thompson@gmail.com',
        phone: '(512) 555-1001',
        address: '123 Oak Lane',
        city: 'Austin',
        state: 'TX',
        zip: '78702',
        notes: 'Referred by neighbor. Prefers morning appointments.',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'James Rivera',
        email: 'j.rivera@outlook.com',
        phone: '(512) 555-1002',
        address: '456 Pine St',
        city: 'Austin',
        state: 'TX',
        zip: '78703',
        notes: 'Investment property owner. Has 3 more rental units to renovate.',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'Emily Chen',
        email: 'emily.chen@icloud.com',
        phone: '(512) 555-1003',
        address: '789 Elm Ave',
        city: 'Round Rock',
        state: 'TX',
        zip: '78664',
        notes: 'New construction home, wants upgrades from builder-grade.',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'David Martinez',
        email: 'david.m@yahoo.com',
        phone: '(512) 555-1004',
        address: '321 Cedar Dr',
        city: 'Georgetown',
        state: 'TX',
        zip: '78626',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'Lisa Anderson',
        email: 'lisa.a@gmail.com',
        phone: '(512) 555-1005',
        address: '654 Birch Ct',
        city: 'Pflugerville',
        state: 'TX',
        zip: '78660',
        notes: 'Repeat customer — did her kitchen last year.',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyA.id,
        name: 'Robert & Karen Hughes',
        email: 'hughes.family@gmail.com',
        phone: '(512) 555-1006',
        address: '900 Magnolia Blvd',
        city: 'Austin',
        state: 'TX',
        zip: '78745',
        notes: 'Older couple, downsizing. Flexible on timeline but fixed budget.',
      },
    }),
  ]);

  // Company B clients
  const clientsB = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyB.id,
        name: 'Mark & Susan Kowalski',
        email: 'kowalski.home@gmail.com',
        phone: '(720) 555-2001',
        address: '2100 Blake St',
        city: 'Denver',
        state: 'CO',
        zip: '80205',
        notes: 'Historic bungalow renovation. Must preserve original trim.',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyB.id,
        name: 'Priya Nair',
        email: 'priya.nair@protonmail.com',
        phone: '(720) 555-2002',
        address: '3400 Tennyson St',
        city: 'Denver',
        state: 'CO',
        zip: '80212',
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyB.id,
        name: 'Carlos Gutierrez',
        email: 'carlos.g@live.com',
        phone: '(720) 555-2003',
        address: '5600 S Broadway',
        city: 'Littleton',
        state: 'CO',
        zip: '80121',
        notes: 'Commercial property — restaurant bathroom remodel.',
      },
    }),
  ]);

  // =========================================================================
  // 6. PROJECTS (varied statuses, types, tiers)
  // =========================================================================
  console.log('  Projects...');

  // --- Company A projects ---
  const projectKitchen = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[0].id,
      title: 'Thompson Kitchen Remodel',
      description: 'Full gut renovation of a 1990s kitchen. Open concept, island, new appliances.',
      projectType: ProjectType.KITCHEN,
      status: ProjectStatus.ESTIMATE_CREATED,
      qualityTier: QualityTier.PREMIUM,
      budgetMin: 18000,
      budgetMax: 32000,
      squareFootage: 180,
      dimensions: '15x12',
      createdAt: daysAgo(14),
    },
  });

  const projectBathroom = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[1].id,
      title: 'Rivera Master Bath',
      description: 'Luxury master bath with walk-in shower, double vanity, heated floors.',
      projectType: ProjectType.BATHROOM,
      status: ProjectStatus.PROPOSAL_SENT,
      qualityTier: QualityTier.LUXURY,
      budgetMin: 12000,
      budgetMax: 25000,
      squareFootage: 110,
      dimensions: '11x10',
      createdAt: daysAgo(21),
    },
  });

  const projectFlooring = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[2].id,
      title: 'Chen Living Room Flooring',
      description: 'Replace builder-grade carpet with LVP throughout main living area.',
      projectType: ProjectType.FLOORING,
      status: ProjectStatus.APPROVED,
      qualityTier: QualityTier.STANDARD,
      budgetMin: 3500,
      budgetMax: 7000,
      squareFootage: 420,
      createdAt: daysAgo(30),
    },
  });

  const projectPainting = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[3].id,
      title: 'Martinez Exterior Paint',
      description: 'Full exterior repaint — two-story stucco home, trim and shutters.',
      projectType: ProjectType.PAINTING,
      status: ProjectStatus.INVOICED,
      qualityTier: QualityTier.PREMIUM,
      budgetMin: 4000,
      budgetMax: 8000,
      createdAt: daysAgo(45),
    },
  });

  const projectRoofing = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[4].id,
      title: 'Anderson Roof Replacement',
      description: 'Tear-off and replace with architectural shingles. Ridge vent install.',
      projectType: ProjectType.ROOFING,
      status: ProjectStatus.COMPLETED,
      qualityTier: QualityTier.STANDARD,
      budgetMin: 8000,
      budgetMax: 14000,
      squareFootage: 2200,
      createdAt: daysAgo(60),
    },
  });

  const projectRoom = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[5].id,
      title: 'Hughes Guest Bedroom Remodel',
      description: 'Convert unused office to guest suite — new flooring, paint, closet system.',
      projectType: ProjectType.ROOM_REMODEL,
      status: ProjectStatus.DRAFT,
      qualityTier: QualityTier.STANDARD,
      budgetMin: 2500,
      budgetMax: 5000,
      squareFootage: 150,
      dimensions: '12x12.5',
      createdAt: daysAgo(2),
    },
  });

  const projectSiding = await prisma.project.create({
    data: {
      companyId: companyA.id,
      clientId: clientsA[0].id,
      title: 'Thompson Siding Replacement',
      description: 'Replace aging wood siding with fiber cement. Wrap and trim.',
      projectType: ProjectType.SIDING,
      status: ProjectStatus.GENERATION_COMPLETE,
      qualityTier: QualityTier.PREMIUM,
      budgetMin: 15000,
      budgetMax: 28000,
      squareFootage: 1800,
      createdAt: daysAgo(5),
    },
  });

  // --- Company B projects ---
  const projectDenverBath = await prisma.project.create({
    data: {
      companyId: companyB.id,
      clientId: clientsB[0].id,
      title: 'Kowalski Bungalow Bath',
      description: 'Restore 1920s bathroom with period fixtures, hex tile, clawfoot tub.',
      projectType: ProjectType.BATHROOM,
      status: ProjectStatus.ESTIMATE_CREATED,
      qualityTier: QualityTier.PREMIUM,
      budgetMin: 10000,
      budgetMax: 20000,
      squareFootage: 65,
      createdAt: daysAgo(10),
    },
  });

  const projectDenverKitchen = await prisma.project.create({
    data: {
      companyId: companyB.id,
      clientId: clientsB[1].id,
      title: 'Nair Modern Kitchen',
      description: 'Sleek contemporary kitchen — flat panel cabinets, waterfall island, under-cab LEDs.',
      projectType: ProjectType.KITCHEN,
      status: ProjectStatus.APPROVED,
      qualityTier: QualityTier.LUXURY,
      budgetMin: 35000,
      budgetMax: 60000,
      squareFootage: 220,
      dimensions: '20x11',
      createdAt: daysAgo(18),
    },
  });

  const projectDenverExterior = await prisma.project.create({
    data: {
      companyId: companyB.id,
      clientId: clientsB[2].id,
      title: 'Gutierrez Restaurant Restroom',
      description: 'Commercial ADA-compliant restroom remodel for small restaurant.',
      projectType: ProjectType.CUSTOM,
      status: ProjectStatus.COMPLETED,
      qualityTier: QualityTier.STANDARD,
      budgetMin: 6000,
      budgetMax: 12000,
      squareFootage: 80,
      createdAt: daysAgo(40),
    },
  });

  // =========================================================================
  // 7. AI GENERATIONS
  // =========================================================================
  console.log('  AI generations...');

  const genKitchen = await prisma.aIGeneration.create({
    data: {
      projectId: projectKitchen.id,
      prompt: 'Modern open-concept kitchen with white shaker cabinets, quartz counters, brass fixtures',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 34200,
      createdAt: daysAgo(13),
    },
  });

  const genBathroom = await prisma.aIGeneration.create({
    data: {
      projectId: projectBathroom.id,
      prompt: 'Luxury spa-style master bath with frameless glass shower and marble tile',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 41800,
      createdAt: daysAgo(20),
    },
  });

  await prisma.aIGeneration.create({
    data: {
      projectId: projectFlooring.id,
      prompt: 'Light oak luxury vinyl plank flooring in open living area',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 28500,
      createdAt: daysAgo(29),
    },
  });

  await prisma.aIGeneration.create({
    data: {
      projectId: projectSiding.id,
      prompt: 'Gray fiber cement lap siding with white trim and black shutters',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 38700,
      createdAt: daysAgo(4),
    },
  });

  await prisma.aIGeneration.create({
    data: {
      projectId: projectDenverBath.id,
      prompt: 'Vintage 1920s bathroom with white subway tile, hex floor, chrome fixtures',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 36100,
      createdAt: daysAgo(9),
    },
  });

  await prisma.aIGeneration.create({
    data: {
      projectId: projectDenverKitchen.id,
      prompt: 'High-end contemporary kitchen with flat-panel walnut cabinets and quartz waterfall island',
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 45200,
      createdAt: daysAgo(17),
    },
  });

  // A failed generation
  await prisma.aIGeneration.create({
    data: {
      projectId: projectRoom.id,
      prompt: 'Cozy guest bedroom with warm gray walls and new carpet',
      status: GenerationStatus.FAILED,
      errorMessage: 'Image generation provider returned empty response',
      createdAt: daysAgo(1),
    },
  });

  // =========================================================================
  // 8. MATERIAL SUGGESTIONS
  // =========================================================================
  console.log('  Material suggestions...');

  const kitchenMaterials = [
    { name: 'White Shaker Cabinets (10x10 set)', category: 'Cabinets', estimatedCost: 3200, unit: 'set', quantity: 1, supplierName: 'Home Depot' },
    { name: 'Quartz Countertop - Calacatta Look', category: 'Countertops', estimatedCost: 45, unit: 'sq ft', quantity: 42, supplierName: 'Floor & Decor' },
    { name: 'LVP Flooring - Natural Oak', category: 'Flooring', estimatedCost: 2.89, unit: 'sq ft', quantity: 190, supplierName: 'Home Depot' },
    { name: 'Subway Tile Backsplash 3x6 White', category: 'Tile', estimatedCost: 1.49, unit: 'sq ft', quantity: 32, supplierName: "Lowe's" },
    { name: 'Brushed Brass Kitchen Faucet', category: 'Fixtures', estimatedCost: 189, unit: 'each', quantity: 1, supplierName: 'Build.com' },
    { name: 'Under-Cabinet LED Light Strip Kit', category: 'Lighting', estimatedCost: 65, unit: 'each', quantity: 2, supplierName: 'Amazon' },
    { name: 'Stainless Undermount Sink 32"', category: 'Fixtures', estimatedCost: 219, unit: 'each', quantity: 1, supplierName: "Lowe's" },
    { name: 'Cabinet Hardware - Brass Pulls (25pk)', category: 'Hardware', estimatedCost: 48, unit: 'set', quantity: 1, supplierName: 'Amazon' },
    { name: 'Interior Paint - Eggshell White (5 gal)', category: 'Paint', estimatedCost: 165, unit: 'each', quantity: 1, supplierName: 'Sherwin-Williams' },
    { name: 'Miscellaneous Supplies', category: 'Other', estimatedCost: 120, unit: 'each', quantity: 1, supplierName: 'Home Depot' },
  ];

  for (let i = 0; i < kitchenMaterials.length; i++) {
    await prisma.materialSuggestion.create({
      data: {
        generationId: genKitchen.id,
        projectId: projectKitchen.id,
        ...kitchenMaterials[i],
        isSelected: true,
        sortOrder: i,
      },
    });
  }

  const bathMaterials = [
    { name: 'Marble Tile 12x24 - Bianco Carrara', category: 'Tile', estimatedCost: 8.50, unit: 'sq ft', quantity: 120, supplierName: 'Floor & Decor' },
    { name: 'Frameless Glass Shower Door 60"', category: 'Fixtures', estimatedCost: 890, unit: 'each', quantity: 1, supplierName: "Lowe's" },
    { name: 'Double Vanity 60" with Top', category: 'Cabinets', estimatedCost: 1100, unit: 'each', quantity: 1, supplierName: 'Home Depot' },
    { name: 'Heated Floor Mat Kit', category: 'Electrical', estimatedCost: 340, unit: 'each', quantity: 1, supplierName: 'Build.com' },
    { name: 'Rain Showerhead + Handheld Combo', category: 'Fixtures', estimatedCost: 275, unit: 'each', quantity: 1, supplierName: 'Wayfair' },
    { name: 'Elongated Toilet - Comfort Height', category: 'Plumbing', estimatedCost: 280, unit: 'each', quantity: 1, supplierName: "Lowe's" },
    { name: 'LED Vanity Mirror 48"', category: 'Lighting', estimatedCost: 320, unit: 'each', quantity: 1, supplierName: 'Amazon' },
    { name: 'Miscellaneous Supplies', category: 'Other', estimatedCost: 150, unit: 'each', quantity: 1, supplierName: 'Home Depot' },
  ];

  for (let i = 0; i < bathMaterials.length; i++) {
    await prisma.materialSuggestion.create({
      data: {
        generationId: genBathroom.id,
        projectId: projectBathroom.id,
        ...bathMaterials[i],
        isSelected: true,
        sortOrder: i,
      },
    });
  }

  // =========================================================================
  // 9. ESTIMATES & LINE ITEMS
  // =========================================================================
  console.log('  Estimates & line items...');

  // Kitchen estimate
  const estKitchen = await prisma.estimate.create({
    data: {
      projectId: projectKitchen.id,
      companyId: companyA.id,
      estimateNumber: 'APX-1001',
      title: 'Kitchen Remodel - Full Scope',
      status: EstimateStatus.DRAFT,
      createdByUserId: mike.id,
      assumptions: 'Existing plumbing and electrical in good condition. No structural changes needed.',
      exclusions: 'Appliances not included. Permit fees not included.',
      notes: 'Quote valid for 30 days.',
      validUntil: daysFromNow(30),
      createdAt: daysAgo(12),
    },
  });

  const kitchenLineItems = [
    { category: LineItemCategory.MATERIALS, name: 'White Shaker Cabinets (10x10)', quantity: 1, unit: 'set', unitCost: 3200, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.MATERIALS, name: 'Quartz Countertop - Calacatta Look', quantity: 42, unit: 'sq ft', unitCost: 45, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.MATERIALS, name: 'LVP Flooring - Natural Oak', quantity: 190, unit: 'sq ft', unitCost: 2.89, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.MATERIALS, name: 'Subway Tile Backsplash', quantity: 32, unit: 'sq ft', unitCost: 1.49, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.MATERIALS, name: 'Fixtures & Hardware Bundle', quantity: 1, unit: 'each', unitCost: 521, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.MATERIALS, name: 'Paint & Miscellaneous', quantity: 1, unit: 'each', unitCost: 285, markupPercent: 0, taxRate: 0.0825 },
    { category: LineItemCategory.LABOR, name: 'Demolition & Disposal', quantity: 8, unit: 'hour', unitCost: 35, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Cabinet Installation', quantity: 16, unit: 'hour', unitCost: 55, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Countertop Templating & Install', quantity: 6, unit: 'hour', unitCost: 50, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Flooring Installation', quantity: 10, unit: 'hour', unitCost: 40, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Tile Backsplash Install', quantity: 6, unit: 'hour', unitCost: 45, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Plumbing Hookup', quantity: 4, unit: 'hour', unitCost: 55, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Electrical & Lighting', quantity: 4, unit: 'hour', unitCost: 50, markupPercent: 0, taxRate: 0 },
    { category: LineItemCategory.LABOR, name: 'Painting & Touch-up', quantity: 6, unit: 'hour', unitCost: 35, markupPercent: 0, taxRate: 0 },
  ];

  let subtotalMaterials = 0;
  let subtotalLabor = 0;
  let taxAmount = 0;

  for (let i = 0; i < kitchenLineItems.length; i++) {
    const item = kitchenLineItems[i];
    const lineTotal = item.quantity * item.unitCost * (1 + item.markupPercent / 100);
    const lineTax = lineTotal * item.taxRate;

    if (item.category === LineItemCategory.MATERIALS) subtotalMaterials += lineTotal;
    else subtotalLabor += lineTotal;
    taxAmount += lineTax;

    await prisma.estimateLineItem.create({
      data: {
        estimateId: estKitchen.id,
        category: item.category,
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        unitCost: item.unitCost,
        markupPercent: item.markupPercent,
        taxRate: item.taxRate,
        lineTotal: Math.round(lineTotal * 100) / 100,
        sortOrder: i,
      },
    });
  }

  await prisma.estimate.update({
    where: { id: estKitchen.id },
    data: {
      subtotalMaterials: Math.round(subtotalMaterials * 100) / 100,
      subtotalLabor: Math.round(subtotalLabor * 100) / 100,
      taxAmount: Math.round(taxAmount * 100) / 100,
      totalAmount: Math.round((subtotalMaterials + subtotalLabor + taxAmount) * 100) / 100,
    },
  });

  // Bathroom estimate — sent
  const estBathroom = await prisma.estimate.create({
    data: {
      projectId: projectBathroom.id,
      companyId: companyA.id,
      estimateNumber: 'APX-1002',
      title: 'Master Bath - Luxury Spa Remodel',
      status: EstimateStatus.SENT,
      createdByUserId: mike.id,
      subtotalMaterials: 4375,
      subtotalLabor: 2800,
      taxAmount: 360.94,
      totalAmount: 7535.94,
      assumptions: 'Subfloor in good condition. No mold remediation needed.',
      exclusions: 'HVAC modifications not included.',
      validUntil: daysFromNow(14),
      createdAt: daysAgo(19),
    },
  });

  // Flooring estimate — approved
  const estFlooring = await prisma.estimate.create({
    data: {
      projectId: projectFlooring.id,
      companyId: companyA.id,
      estimateNumber: 'APX-1003',
      title: 'LVP Flooring - Main Level',
      status: EstimateStatus.APPROVED,
      createdByUserId: jessica.id,
      subtotalMaterials: 1580,
      subtotalLabor: 960,
      taxAmount: 130.35,
      totalAmount: 2670.35,
      validUntil: daysFromNow(7),
      createdAt: daysAgo(28),
    },
  });

  // Painting estimate — approved
  const estPainting = await prisma.estimate.create({
    data: {
      projectId: projectPainting.id,
      companyId: companyA.id,
      estimateNumber: 'APX-1004',
      title: 'Exterior Paint - Full House',
      status: EstimateStatus.APPROVED,
      createdByUserId: mike.id,
      subtotalMaterials: 1850,
      subtotalLabor: 2100,
      taxAmount: 152.63,
      totalAmount: 4102.63,
      createdAt: daysAgo(42),
    },
  });

  // Roofing estimate — approved
  const estRoofing = await prisma.estimate.create({
    data: {
      projectId: projectRoofing.id,
      companyId: companyA.id,
      estimateNumber: 'APX-1005',
      title: 'Roof Replacement - Architectural Shingles',
      status: EstimateStatus.APPROVED,
      createdByUserId: mike.id,
      subtotalMaterials: 5200,
      subtotalLabor: 3600,
      taxAmount: 429,
      totalAmount: 9229,
      createdAt: daysAgo(55),
    },
  });

  // Company B estimates
  await prisma.estimate.create({
    data: {
      projectId: projectDenverBath.id,
      companyId: companyB.id,
      estimateNumber: 'SHS-5001',
      title: 'Vintage Bath Restoration',
      status: EstimateStatus.DRAFT,
      createdByUserId: rachel.id,
      subtotalMaterials: 3900,
      subtotalLabor: 2400,
      taxAmount: 113.10,
      totalAmount: 6413.10,
      createdAt: daysAgo(8),
    },
  });

  const estDenverKitchen = await prisma.estimate.create({
    data: {
      projectId: projectDenverKitchen.id,
      companyId: companyB.id,
      estimateNumber: 'SHS-5002',
      title: 'Contemporary Kitchen - Full Scope',
      status: EstimateStatus.APPROVED,
      createdByUserId: rachel.id,
      subtotalMaterials: 22500,
      subtotalLabor: 8400,
      taxAmount: 652.50,
      totalAmount: 31552.50,
      createdAt: daysAgo(15),
    },
  });

  await prisma.estimate.create({
    data: {
      projectId: projectDenverExterior.id,
      companyId: companyB.id,
      estimateNumber: 'SHS-5003',
      title: 'ADA Restroom Remodel',
      status: EstimateStatus.APPROVED,
      createdByUserId: derek.id,
      subtotalMaterials: 3100,
      subtotalLabor: 2200,
      taxAmount: 89.90,
      totalAmount: 5389.90,
      createdAt: daysAgo(38),
    },
  });

  // =========================================================================
  // 10. PROPOSALS
  // =========================================================================
  console.log('  Proposals...');

  await prisma.proposal.create({
    data: {
      estimateId: estBathroom.id,
      projectId: projectBathroom.id,
      companyId: companyA.id,
      proposalNumber: 'APX-PROP-3001',
      title: 'Master Bath Renovation Proposal',
      status: ProposalStatus.SENT,
      shareToken: 'seed-share-token-001',
      introText: 'Thank you for choosing Apex Remodeling for your master bathroom renovation. We are excited to bring your spa-inspired vision to life.',
      scopeOfWork: '• Full demolition of existing bathroom\n• New tile flooring with radiant heat\n• Walk-in frameless glass shower\n• Double vanity with quartz top\n• New plumbing fixtures throughout\n• LED mirror and vanity lighting\n• Fresh paint and trim',
      timelineText: 'Estimated duration: 3-4 weeks from start date. We will schedule around your availability.',
      termsAndConditions: '50% deposit required to begin. Balance due upon completion. 1-year warranty on labor.',
      sentAt: daysAgo(18),
      expiresAt: daysFromNow(12),
      createdAt: daysAgo(19),
    },
  });

  await prisma.proposal.create({
    data: {
      estimateId: estFlooring.id,
      projectId: projectFlooring.id,
      companyId: companyA.id,
      proposalNumber: 'APX-PROP-3002',
      title: 'Living Room Flooring Proposal',
      status: ProposalStatus.APPROVED,
      shareToken: 'seed-share-token-002',
      introText: 'Here is our proposal for replacing your carpet with luxury vinyl plank flooring.',
      scopeOfWork: '• Remove existing carpet and pad\n• Prep and level subfloor\n• Install LVP flooring with underlayment\n• Install transition strips at doorways\n• Reinstall baseboards',
      timelineText: '2-3 days for completion.',
      termsAndConditions: 'Full payment due upon completion. 1-year warranty on labor.',
      sentAt: daysAgo(26),
      viewedAt: daysAgo(25),
      respondedAt: daysAgo(24),
      createdAt: daysAgo(27),
    },
  });

  await prisma.proposal.create({
    data: {
      estimateId: estDenverKitchen.id,
      projectId: projectDenverKitchen.id,
      companyId: companyB.id,
      proposalNumber: 'SHS-PROP-7001',
      title: 'Modern Kitchen Transformation',
      status: ProposalStatus.APPROVED,
      shareToken: 'seed-share-token-003',
      introText: 'We are thrilled to present our plan for your dream kitchen.',
      scopeOfWork: '• Complete demolition\n• Custom flat-panel walnut cabinetry\n• Waterfall quartz island\n• Premium appliance installation\n• Under-cabinet LED lighting\n• Plumbing and electrical upgrades',
      timelineText: '6-8 weeks estimated.',
      termsAndConditions: '30% deposit, 30% at rough-in, 40% at completion.',
      sentAt: daysAgo(14),
      viewedAt: daysAgo(13),
      respondedAt: daysAgo(12),
      createdAt: daysAgo(15),
    },
  });

  // =========================================================================
  // 11. INVOICES & LINE ITEMS
  // =========================================================================
  console.log('  Invoices...');

  // Painting invoice — paid
  const invPainting = await prisma.invoice.create({
    data: {
      estimateId: estPainting.id,
      projectId: projectPainting.id,
      companyId: companyA.id,
      clientId: clientsA[3].id,
      invoiceNumber: 'APX-INV-2001',
      status: InvoiceStatus.PAID,
      subtotal: 3950,
      taxAmount: 152.63,
      totalAmount: 4102.63,
      amountPaid: 4102.63,
      amountDue: 0,
      issuedDate: daysAgo(35),
      dueDate: daysAgo(5),
      paidAt: daysAgo(10),
      sentAt: daysAgo(35),
      notes: 'Thank you for your prompt payment!',
      paymentInstructions: 'Zelle to info@apexremodeling.com or check payable to Apex Remodeling Co.',
      createdAt: daysAgo(35),
    },
  });

  await prisma.invoiceLineItem.createMany({
    data: [
      { invoiceId: invPainting.id, name: 'Exterior Paint & Primer', quantity: 1, unit: 'lot', unitCost: 850, lineTotal: 850, sortOrder: 0 },
      { invoiceId: invPainting.id, name: 'Pressure Washing & Prep', quantity: 1, unit: 'lot', unitCost: 500, lineTotal: 500, sortOrder: 1 },
      { invoiceId: invPainting.id, name: 'Caulking & Repair Materials', quantity: 1, unit: 'lot', unitCost: 200, lineTotal: 200, sortOrder: 2 },
      { invoiceId: invPainting.id, name: 'Supplies & Equipment', quantity: 1, unit: 'lot', unitCost: 300, lineTotal: 300, sortOrder: 3 },
      { invoiceId: invPainting.id, name: 'Painting Labor (2 painters, 3 days)', quantity: 48, unit: 'hour', unitCost: 43.75, lineTotal: 2100, sortOrder: 4 },
    ],
  });

  // Roofing invoice — paid
  const invRoofing = await prisma.invoice.create({
    data: {
      estimateId: estRoofing.id,
      projectId: projectRoofing.id,
      companyId: companyA.id,
      clientId: clientsA[4].id,
      invoiceNumber: 'APX-INV-2002',
      status: InvoiceStatus.PAID,
      subtotal: 8800,
      taxAmount: 429,
      totalAmount: 9229,
      amountPaid: 9229,
      amountDue: 0,
      issuedDate: daysAgo(50),
      dueDate: daysAgo(20),
      paidAt: daysAgo(22),
      sentAt: daysAgo(50),
      paymentInstructions: 'Zelle to info@apexremodeling.com or check payable to Apex Remodeling Co.',
      createdAt: daysAgo(50),
    },
  });

  await prisma.invoiceLineItem.createMany({
    data: [
      { invoiceId: invRoofing.id, name: 'Architectural Shingles (22 sq)', quantity: 22, unit: 'square', unitCost: 140, lineTotal: 3080, sortOrder: 0 },
      { invoiceId: invRoofing.id, name: 'Underlayment & Ice Shield', quantity: 1, unit: 'lot', unitCost: 850, lineTotal: 850, sortOrder: 1 },
      { invoiceId: invRoofing.id, name: 'Ridge Vent & Flashing', quantity: 1, unit: 'lot', unitCost: 620, lineTotal: 620, sortOrder: 2 },
      { invoiceId: invRoofing.id, name: 'Drip Edge & Fasteners', quantity: 1, unit: 'lot', unitCost: 350, lineTotal: 350, sortOrder: 3 },
      { invoiceId: invRoofing.id, name: 'Dumpster & Disposal', quantity: 1, unit: 'each', unitCost: 300, lineTotal: 300, sortOrder: 4 },
      { invoiceId: invRoofing.id, name: 'Roofing Labor (crew of 4, 5 days)', quantity: 1, unit: 'lot', unitCost: 3600, lineTotal: 3600, sortOrder: 5 },
    ],
  });

  // Flooring invoice — sent, partially paid
  const invFlooring = await prisma.invoice.create({
    data: {
      estimateId: estFlooring.id,
      projectId: projectFlooring.id,
      companyId: companyA.id,
      clientId: clientsA[2].id,
      invoiceNumber: 'APX-INV-2003',
      status: InvoiceStatus.PARTIALLY_PAID,
      subtotal: 2540,
      taxAmount: 130.35,
      totalAmount: 2670.35,
      amountPaid: 1335,
      amountDue: 1335.35,
      issuedDate: daysAgo(7),
      dueDate: daysFromNow(23),
      sentAt: daysAgo(7),
      notes: '50% deposit received. Balance due upon completion.',
      paymentInstructions: 'Zelle to info@apexremodeling.com or check payable to Apex Remodeling Co.',
      createdAt: daysAgo(7),
    },
  });

  // Denver — completed restaurant invoice
  await prisma.invoice.create({
    data: {
      projectId: projectDenverExterior.id,
      companyId: companyB.id,
      clientId: clientsB[2].id,
      invoiceNumber: 'SHS-INV-6001',
      status: InvoiceStatus.PAID,
      subtotal: 5300,
      taxAmount: 89.90,
      totalAmount: 5389.90,
      amountPaid: 5389.90,
      amountDue: 0,
      issuedDate: daysAgo(32),
      dueDate: daysAgo(2),
      paidAt: daysAgo(5),
      sentAt: daysAgo(32),
      paymentInstructions: 'Wire transfer or check payable to Summit Home Solutions LLC.',
      createdAt: daysAgo(32),
    },
  });

  // =========================================================================
  // 12. PRICING PROFILES & LABOR RATES
  // =========================================================================
  console.log('  Pricing profiles...');

  const profileResidential = await prisma.pricingProfile.create({
    data: {
      companyId: companyA.id,
      name: 'Standard Residential',
      defaultMarkupPercent: 15,
      contingencyPercent: 10,
      wasteFactor: 5,
      isDefault: true,
    },
  });

  await prisma.laborRateRule.createMany({
    data: [
      { pricingProfileId: profileResidential.id, category: 'General Labor', ratePerHour: 35, minimumHours: 2 },
      { pricingProfileId: profileResidential.id, category: 'Carpentry', ratePerHour: 50, minimumHours: 4 },
      { pricingProfileId: profileResidential.id, category: 'Plumbing', ratePerHour: 55, minimumHours: 2 },
      { pricingProfileId: profileResidential.id, category: 'Electrical', ratePerHour: 50, minimumHours: 2 },
      { pricingProfileId: profileResidential.id, category: 'Tile / Stone', ratePerHour: 45, minimumHours: 4 },
      { pricingProfileId: profileResidential.id, category: 'Painting', ratePerHour: 35, minimumHours: 4 },
    ],
  });

  const profilePremium = await prisma.pricingProfile.create({
    data: {
      companyId: companyA.id,
      name: 'Premium / Custom',
      defaultMarkupPercent: 25,
      contingencyPercent: 15,
      wasteFactor: 8,
      isDefault: false,
    },
  });

  await prisma.laborRateRule.createMany({
    data: [
      { pricingProfileId: profilePremium.id, category: 'General Labor', ratePerHour: 45, minimumHours: 2 },
      { pricingProfileId: profilePremium.id, category: 'Carpentry', ratePerHour: 65, minimumHours: 4 },
      { pricingProfileId: profilePremium.id, category: 'Plumbing', ratePerHour: 70, minimumHours: 2 },
      { pricingProfileId: profilePremium.id, category: 'Electrical', ratePerHour: 65, minimumHours: 2 },
    ],
  });

  // Company B profile
  const profileSummit = await prisma.pricingProfile.create({
    data: {
      companyId: companyB.id,
      name: 'Denver Standard',
      defaultMarkupPercent: 20,
      contingencyPercent: 10,
      wasteFactor: 5,
      isDefault: true,
    },
  });

  await prisma.laborRateRule.createMany({
    data: [
      { pricingProfileId: profileSummit.id, category: 'General Labor', ratePerHour: 40, minimumHours: 2 },
      { pricingProfileId: profileSummit.id, category: 'Carpentry', ratePerHour: 55, minimumHours: 4 },
      { pricingProfileId: profileSummit.id, category: 'Plumbing', ratePerHour: 60, minimumHours: 2 },
    ],
  });

  // =========================================================================
  // 13. ACTIVITY LOG
  // =========================================================================
  console.log('  Activity logs...');

  const activityEntries = [
    { projectId: projectKitchen.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectKitchen.id, createdAt: daysAgo(14) },
    { projectId: projectKitchen.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.IMAGE_UPLOADED, description: 'Photo uploaded for AI generation', entityType: 'Asset', createdAt: daysAgo(13) },
    { projectId: projectKitchen.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.GENERATION_STARTED, description: 'AI preview generation started', entityType: 'AIGeneration', createdAt: daysAgo(13) },
    { projectId: projectKitchen.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.GENERATION_COMPLETED, description: 'AI preview generation completed', entityType: 'AIGeneration', createdAt: daysAgo(13) },
    { projectId: projectKitchen.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.ESTIMATE_CREATED, description: 'Estimate APX-1001 created', entityType: 'Estimate', entityId: estKitchen.id, createdAt: daysAgo(12) },
    { projectId: projectBathroom.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectBathroom.id, createdAt: daysAgo(21) },
    { projectId: projectBathroom.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.GENERATION_COMPLETED, description: 'AI preview generation completed', entityType: 'AIGeneration', createdAt: daysAgo(20) },
    { projectId: projectBathroom.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.ESTIMATE_CREATED, description: 'Estimate APX-1002 created', entityType: 'Estimate', entityId: estBathroom.id, createdAt: daysAgo(19) },
    { projectId: projectBathroom.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.PROPOSAL_SENT, description: 'Proposal sent to client', entityType: 'Proposal', createdAt: daysAgo(18) },
    { projectId: projectFlooring.id, companyId: companyA.id, userId: jessica.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectFlooring.id, createdAt: daysAgo(30) },
    { projectId: projectFlooring.id, companyId: companyA.id, userId: jessica.id, action: ActivityAction.ESTIMATE_CREATED, description: 'Estimate APX-1003 created', entityType: 'Estimate', entityId: estFlooring.id, createdAt: daysAgo(28) },
    { projectId: projectFlooring.id, companyId: companyA.id, userId: jessica.id, action: ActivityAction.PROPOSAL_APPROVED, description: 'Client approved the proposal', entityType: 'Proposal', createdAt: daysAgo(24) },
    { projectId: projectFlooring.id, companyId: companyA.id, userId: jessica.id, action: ActivityAction.INVOICE_CREATED, description: 'Invoice APX-INV-2003 created', entityType: 'Invoice', entityId: invFlooring.id, createdAt: daysAgo(7) },
    { projectId: projectPainting.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectPainting.id, createdAt: daysAgo(45) },
    { projectId: projectPainting.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.INVOICE_PAID, description: 'Invoice APX-INV-2001 marked as paid', entityType: 'Invoice', entityId: invPainting.id, createdAt: daysAgo(10) },
    { projectId: projectRoofing.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectRoofing.id, createdAt: daysAgo(60) },
    { projectId: projectRoofing.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.INVOICE_PAID, description: 'Invoice APX-INV-2002 marked as paid', entityType: 'Invoice', entityId: invRoofing.id, createdAt: daysAgo(22) },
    { projectId: projectRoofing.id, companyId: companyA.id, userId: mike.id, action: ActivityAction.STATUS_CHANGED, description: 'Project marked as completed', entityType: 'Project', entityId: projectRoofing.id, createdAt: daysAgo(20) },
    { projectId: projectDenverKitchen.id, companyId: companyB.id, userId: rachel.id, action: ActivityAction.CREATED, description: 'Project created', entityType: 'Project', entityId: projectDenverKitchen.id, createdAt: daysAgo(18) },
    { projectId: projectDenverKitchen.id, companyId: companyB.id, userId: rachel.id, action: ActivityAction.PROPOSAL_APPROVED, description: 'Client approved the kitchen proposal', entityType: 'Proposal', createdAt: daysAgo(12) },
    { projectId: projectDenverExterior.id, companyId: companyB.id, userId: derek.id, action: ActivityAction.INVOICE_PAID, description: 'Invoice SHS-INV-6001 paid in full', entityType: 'Invoice', createdAt: daysAgo(5) },
  ];

  await prisma.activityLogEntry.createMany({ data: activityEntries });

  // =========================================================================
  // 14. PAYWALL IMPRESSIONS
  // =========================================================================
  console.log('  Paywall impressions...');

  await prisma.paywallImpression.createMany({
    data: [
      { userId: jessica.id, companyId: companyA.id, placement: 'GENERATION_LIMIT_HIT', action: 'DISMISSED', createdAt: daysAgo(6) },
      { userId: jessica.id, companyId: companyA.id, placement: 'POST_FIRST_GENERATION', action: 'DISMISSED', createdAt: daysAgo(8) },
      { userId: tom.id, companyId: companyA.id, placement: 'INVOICE_LOCKED', action: 'DISMISSED', createdAt: daysAgo(3) },
      { userId: derek.id, companyId: companyB.id, placement: 'ONBOARDING_SOFT_GATE', action: 'STARTED_TRIAL', createdAt: daysAgo(3) },
    ],
  });

  // =========================================================================
  // 15. USAGE EVENTS
  // =========================================================================
  console.log('  Usage events...');

  await prisma.usageEvent.createMany({
    data: [
      { userId: jessica.id, companyId: companyA.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(8) },
      { userId: mike.id, companyId: companyA.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(13) },
      { userId: mike.id, companyId: companyA.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(4) },
      { userId: mike.id, companyId: companyA.id, metricCode: UsageMetricCode.QUOTE_EXPORT, quantity: 1, createdAt: daysAgo(12) },
      { userId: mike.id, companyId: companyA.id, metricCode: UsageMetricCode.QUOTE_EXPORT, quantity: 1, createdAt: daysAgo(7) },
      { userId: rachel.id, companyId: companyB.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(17) },
      { userId: rachel.id, companyId: companyB.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(9) },
      { userId: rachel.id, companyId: companyB.id, metricCode: UsageMetricCode.QUOTE_EXPORT, quantity: 1, createdAt: daysAgo(15) },
      { userId: derek.id, companyId: companyB.id, metricCode: UsageMetricCode.AI_GENERATION, quantity: 1, createdAt: daysAgo(2) },
    ],
  });

  // =========================================================================
  // Done
  // =========================================================================
  console.log('\n✅ Seed completed successfully!');
  console.log('');
  console.log('   Test accounts (password: demo1234):');
  console.log('   ──────────────────────────────────────');
  console.log('   mike@apexremodeling.com    — Owner, Pro Monthly (Apex)');
  console.log('   jessica@apexremodeling.com — Estimator, Free (Apex)');
  console.log('   tom@apexremodeling.com     — Viewer, Free (Apex)');
  console.log('   rachel@summithome.co       — Owner, Pro Annual (Summit)');
  console.log('   derek@summithome.co        — Admin, Trial Active (Summit)');
  console.log('');
}

main()
  .catch((e) => {
    console.error('Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
