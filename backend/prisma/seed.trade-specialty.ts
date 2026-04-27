import {
  PrismaClient,
  PlanCode,
  UsageMetricCode,
  ProjectType,
  ProjectStatus,
  QualityTier,
  EstimateStatus,
  GenerationStatus,
  EntitlementStatus,
  UserRole,
} from "@prisma/client";

type Plan = { id: string };

interface SeedDeps {
  passwordHash: string;
  proMonthlyPlan: Plan;
  proAnnualPlan: Plan;
  freePlan: Plan;
}

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

/**
 * Seeds four trade-specialty companies + 15 additional users so the
 * total user count reaches 20. Each company exercises a distinct slice
 * of the new schema:
 *   - Verdant Landscapes  (LANDSCAPING + LAWN_CARE recurring)
 *   - GreenSweep          (LAWN_CARE recurring B2B / HOA)
 *   - Crown Roofing       (ROOFING with measured roofAreaSqFt)
 *   - Bayside Builders    (EXTERIOR + ROOM_REMODEL)
 *
 * Also patches the existing Apex / Summit companies with the new
 * `taxInclusivePricing` and `appearanceMode` columns so every Company
 * row in dev tracks them.
 */
export async function seedTradeSpecialty(
  prisma: PrismaClient,
  deps: SeedDeps,
): Promise<void> {
  const { passwordHash, proMonthlyPlan, proAnnualPlan, freePlan } = deps;
  console.log("  Patching existing companies with new columns...");

  // Patch Apex and Summit (created earlier in seed.ts main()).
  await prisma.company.updateMany({
    where: { id: "seed-company-apex" },
    data: { taxInclusivePricing: false, appearanceMode: "system" },
  });
  await prisma.company.updateMany({
    where: { id: "seed-company-summit" },
    data: { taxInclusivePricing: false, appearanceMode: "dark" },
  });

  console.log("  Trade-specialty companies (4)...");

  const companyC = await prisma.company.upsert({
    where: { id: "seed-company-verdant" },
    update: {},
    create: {
      id: "seed-company-verdant",
      name: "Verdant Landscapes",
      phone: "(612) 555-0300",
      email: "studio@verdantmn.com",
      address: "845 Lake St",
      city: "Minneapolis",
      state: "MN",
      zip: "55408",
      primaryColor: "#22C55E",
      secondaryColor: "#1A2E1A",
      estimatePrefix: "VRD",
      invoicePrefix: "VRD-INV",
      proposalPrefix: "VRD-PROP",
      defaultTaxRate: 0.06875,
      defaultMarkupPercent: 22,
      nextEstimateNumber: 4001,
      nextInvoiceNumber: 8001,
      nextProposalNumber: 9001,
      defaultLanguage: "en",
      timezone: "America/Chicago",
      websiteUrl: "https://verdantmn.com",
      taxLabel: "MN Sales Tax",
      taxInclusivePricing: false,
      appearanceMode: "light",
    },
  });

  const companyD = await prisma.company.upsert({
    where: { id: "seed-company-greensweep" },
    update: {},
    create: {
      id: "seed-company-greensweep",
      name: "GreenSweep Lawn Care",
      phone: "(602) 555-0400",
      email: "office@greensweep.com",
      address: "2200 N 7th St",
      city: "Phoenix",
      state: "AZ",
      zip: "85006",
      primaryColor: "#15803D",
      secondaryColor: "#1E293B",
      estimatePrefix: "GSW",
      invoicePrefix: "GSW-INV",
      proposalPrefix: "GSW-PROP",
      defaultTaxRate: 0.086,
      defaultMarkupPercent: 18,
      nextEstimateNumber: 12001,
      nextInvoiceNumber: 13001,
      nextProposalNumber: 14001,
      defaultLanguage: "en",
      timezone: "America/Phoenix",
      websiteUrl: "https://greensweep.com",
      taxLabel: "AZ TPT",
      taxInclusivePricing: false,
      appearanceMode: "system",
    },
  });

  const companyE = await prisma.company.upsert({
    where: { id: "seed-company-crown" },
    update: {},
    create: {
      id: "seed-company-crown",
      name: "Crown Roofing & Exteriors",
      phone: "(404) 555-0500",
      email: "admin@crownroofs.com",
      address: "510 Peachtree Industrial Blvd",
      city: "Atlanta",
      state: "GA",
      zip: "30303",
      primaryColor: "#FF9230",
      secondaryColor: "#0F172A",
      estimatePrefix: "CRN",
      invoicePrefix: "CRN-INV",
      proposalPrefix: "CRN-PROP",
      defaultTaxRate: 0.089,
      defaultMarkupPercent: 18,
      nextEstimateNumber: 16001,
      nextInvoiceNumber: 17001,
      nextProposalNumber: 18001,
      defaultLanguage: "en",
      timezone: "America/New_York",
      websiteUrl: "https://crownroofs.com",
      taxLabel: "GA Sales Tax",
      taxInclusivePricing: false,
      appearanceMode: "dark",
    },
  });

  const companyF = await prisma.company.upsert({
    where: { id: "seed-company-bayside" },
    update: {},
    create: {
      id: "seed-company-bayside",
      name: "Bayside Builders",
      phone: "(813) 555-0600",
      email: "team@baysidebuilders.com",
      address: "300 Bayshore Blvd",
      city: "Tampa",
      state: "FL",
      zip: "33606",
      primaryColor: "#0EA5E9",
      secondaryColor: "#0C4A6E",
      estimatePrefix: "BAY",
      invoicePrefix: "BAY-INV",
      proposalPrefix: "BAY-PROP",
      defaultTaxRate: 0.075,
      defaultMarkupPercent: 20,
      nextEstimateNumber: 20001,
      nextInvoiceNumber: 21001,
      nextProposalNumber: 22001,
      defaultLanguage: "en",
      timezone: "America/New_York",
      websiteUrl: "https://baysidebuilders.com",
      taxLabel: "FL Sales Tax",
      taxInclusivePricing: false,
      appearanceMode: "system",
    },
  });

  console.log("  15 additional users + entitlements...");

  async function makeUser(opts: {
    id: string;
    email: string;
    fullName: string;
    companyId: string;
    role: UserRole;
    phone: string;
    plan: "pro_monthly" | "pro_annual" | "free" | "trial";
  }) {
    const user = await prisma.user.upsert({
      where: { email: opts.email },
      update: {},
      create: {
        id: opts.id,
        companyId: opts.companyId,
        email: opts.email,
        passwordHash,
        fullName: opts.fullName,
        role: opts.role,
        phone: opts.phone,
      },
    });

    let planId = freePlan.id;
    let status: EntitlementStatus = EntitlementStatus.FREE;
    let storeProductId: string | undefined;
    let trialEndsAt: Date | undefined;
    let renewalDate: Date | undefined;
    let startsAt: Date | undefined;

    switch (opts.plan) {
      case "pro_monthly":
        planId = proMonthlyPlan.id;
        status = EntitlementStatus.PRO_ACTIVE;
        storeProductId = "proestimate.pro.monthly";
        renewalDate = daysFromNow(20);
        startsAt = daysAgo(10);
        break;
      case "pro_annual":
        planId = proAnnualPlan.id;
        status = EntitlementStatus.PRO_ACTIVE;
        storeProductId = "proestimate.pro.annual";
        renewalDate = daysFromNow(280);
        startsAt = daysAgo(85);
        break;
      case "trial":
        planId = proMonthlyPlan.id;
        status = EntitlementStatus.TRIAL_ACTIVE;
        storeProductId = "proestimate.pro.monthly";
        trialEndsAt = daysFromNow(5);
        startsAt = daysAgo(2);
        break;
      case "free":
      default:
        break;
    }

    await prisma.userEntitlement.upsert({
      where: { userId: user.id },
      update: {},
      create: {
        userId: user.id,
        companyId: opts.companyId,
        planId,
        status,
        storeProductId,
        trialEndsAt,
        renewalDate,
        startsAt,
        isAutoRenewEnabled: opts.plan !== "free",
        source: opts.plan === "free" ? undefined : "APP_STORE",
        environment: opts.plan === "free" ? undefined : "Sandbox",
        originalTransactionId:
          opts.plan === "free" ? undefined : `seed-txn-${user.id}`,
        latestTransactionId:
          opts.plan === "free" ? undefined : `seed-txn-${user.id}`,
      },
    });

    if (opts.plan === "free") {
      for (const metric of [
        UsageMetricCode.AI_GENERATION,
        UsageMetricCode.QUOTE_EXPORT,
      ]) {
        await prisma.usageBucket.upsert({
          where: {
            userId_companyId_metricCode_source: {
              userId: user.id,
              companyId: opts.companyId,
              metricCode: metric,
              source: "STARTER_CREDITS",
            },
          },
          update: {},
          create: {
            userId: user.id,
            companyId: opts.companyId,
            metricCode: metric,
            includedQuantity: 3,
            consumedQuantity: 0,
            source: "STARTER_CREDITS",
          },
        });
      }
    }
    return user;
  }

  // Verdant — 4 users
  const liam = await makeUser({
    id: "seed-user-liam",
    email: "liam@verdantmn.com",
    fullName: "Liam Anderson",
    companyId: companyC.id,
    role: UserRole.OWNER,
    phone: "(612) 555-0301",
    plan: "pro_monthly",
  });
  const aisha = await makeUser({
    id: "seed-user-aisha",
    email: "aisha@verdantmn.com",
    fullName: "Aisha Patel",
    companyId: companyC.id,
    role: UserRole.ESTIMATOR,
    phone: "(612) 555-0302",
    plan: "free",
  });
  const carlosM = await makeUser({
    id: "seed-user-carlos-m",
    email: "carlos@verdantmn.com",
    fullName: "Carlos Morales",
    companyId: companyC.id,
    role: UserRole.ADMIN,
    phone: "(612) 555-0303",
    plan: "pro_annual",
  });
  const jenny = await makeUser({
    id: "seed-user-jenny",
    email: "jenny@verdantmn.com",
    fullName: "Jenny Liu",
    companyId: companyC.id,
    role: UserRole.VIEWER,
    phone: "(612) 555-0304",
    plan: "free",
  });

  // GreenSweep — 4 users
  const marcusC = await makeUser({
    id: "seed-user-marcus-c",
    email: "marcus@greensweep.com",
    fullName: "Marcus Cole",
    companyId: companyD.id,
    role: UserRole.OWNER,
    phone: "(602) 555-0401",
    plan: "pro_annual",
  });
  const diana = await makeUser({
    id: "seed-user-diana",
    email: "diana@greensweep.com",
    fullName: "Diana Romero",
    companyId: companyD.id,
    role: UserRole.ESTIMATOR,
    phone: "(602) 555-0402",
    plan: "trial",
  });
  const tyler = await makeUser({
    id: "seed-user-tyler",
    email: "tyler@greensweep.com",
    fullName: "Tyler Brooks",
    companyId: companyD.id,
    role: UserRole.ADMIN,
    phone: "(602) 555-0403",
    plan: "free",
  });
  const brittany = await makeUser({
    id: "seed-user-brittany",
    email: "brittany@greensweep.com",
    fullName: "Brittany White",
    companyId: companyD.id,
    role: UserRole.VIEWER,
    phone: "(602) 555-0404",
    plan: "free",
  });

  // Crown — 4 users
  const william = await makeUser({
    id: "seed-user-william",
    email: "william@crownroofs.com",
    fullName: "William Carter",
    companyId: companyE.id,
    role: UserRole.OWNER,
    phone: "(404) 555-0501",
    plan: "pro_monthly",
  });
  const sophia = await makeUser({
    id: "seed-user-sophia",
    email: "sophia@crownroofs.com",
    fullName: "Sophia Bennett",
    companyId: companyE.id,
    role: UserRole.ESTIMATOR,
    phone: "(404) 555-0502",
    plan: "pro_monthly",
  });
  const marcusL = await makeUser({
    id: "seed-user-marcus-l",
    email: "marcusl@crownroofs.com",
    fullName: "Marcus Lee",
    companyId: companyE.id,
    role: UserRole.ADMIN,
    phone: "(404) 555-0503",
    plan: "free",
  });
  const olivia = await makeUser({
    id: "seed-user-olivia",
    email: "olivia@crownroofs.com",
    fullName: "Olivia Wright",
    companyId: companyE.id,
    role: UserRole.VIEWER,
    phone: "(404) 555-0504",
    plan: "free",
  });

  // Bayside — 3 users (15 total here)
  const anthony = await makeUser({
    id: "seed-user-anthony",
    email: "anthony@baysidebuilders.com",
    fullName: "Anthony Russo",
    companyId: companyF.id,
    role: UserRole.OWNER,
    phone: "(813) 555-0601",
    plan: "pro_annual",
  });
  const mariaG = await makeUser({
    id: "seed-user-maria-g",
    email: "maria@baysidebuilders.com",
    fullName: "Maria Gomez",
    companyId: companyF.id,
    role: UserRole.ESTIMATOR,
    phone: "(813) 555-0602",
    plan: "trial",
  });
  const devon = await makeUser({
    id: "seed-user-devon",
    email: "devon@baysidebuilders.com",
    fullName: "Devon Walker",
    companyId: companyF.id,
    role: UserRole.VIEWER,
    phone: "(813) 555-0603",
    plan: "free",
  });

  console.log("  Trade-specialty clients...");

  const clientsC = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyC.id,
        name: "Lakeside HOA",
        email: "board@lakesidehoa.org",
        phone: "(612) 555-3001",
        address: "12 Lakeside Pkwy",
        city: "Minneapolis",
        state: "MN",
        zip: "55408",
        notes: "Common-area maintenance contracts. 4-acre common.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyC.id,
        name: "Henrik Bergstrom",
        email: "henrik@bergstrom.com",
        phone: "(612) 555-3002",
        address: "4500 Linden Hills Blvd",
        city: "Minneapolis",
        state: "MN",
        zip: "55410",
        notes: "Front yard hardscape + planting refresh.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyC.id,
        name: "Maple Grove Office Park",
        email: "fm@mapleparkoffice.com",
        phone: "(763) 555-3003",
        address: "8800 Hemlock Ln",
        city: "Maple Grove",
        state: "MN",
        zip: "55369",
        notes: "Commercial entry circle replant.",
      },
    }),
  ]);

  const clientsD = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyD.id,
        name: "Sun Valley HOA",
        email: "admin@sunvalleyhoa.org",
        phone: "(602) 555-4001",
        address: "1500 W Indian School Rd",
        city: "Phoenix",
        state: "AZ",
        zip: "85015",
        notes: "120-unit HOA common-area route.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyD.id,
        name: "Desert Bloom Apartments",
        email: "pm@desertbloomapts.com",
        phone: "(602) 555-4002",
        address: "4400 N Tatum Blvd",
        city: "Phoenix",
        state: "AZ",
        zip: "85018",
        notes: "3-property portfolio.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyD.id,
        name: "Camelback Office Plaza",
        email: "fm@camelbackplaza.com",
        phone: "(602) 555-4003",
        address: "6000 E Camelback Rd",
        city: "Phoenix",
        state: "AZ",
        zip: "85018",
        notes: "Commercial weekly + quarterly.",
      },
    }),
  ]);

  const clientsE = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyE.id,
        name: "Marcus Greene",
        email: "marcus.g@gmail.com",
        phone: "(404) 555-5001",
        address: "2400 Peachtree Rd NE",
        city: "Atlanta",
        state: "GA",
        zip: "30305",
        notes: "Storm damage scout.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyE.id,
        name: "Hannah Whitfield",
        email: "hannah.w@yahoo.com",
        phone: "(404) 555-5002",
        address: "6 Sentinel Pl NW",
        city: "Atlanta",
        state: "GA",
        zip: "30327",
        notes: "Architectural shingle replace.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyE.id,
        name: "Brookhaven Townhomes",
        email: "pm@brookhaventh.com",
        phone: "(404) 555-5003",
        address: "4100 Peachtree Industrial",
        city: "Atlanta",
        state: "GA",
        zip: "30319",
        notes: "Multi-building roof RFP.",
      },
    }),
  ]);

  const clientsF = await Promise.all([
    prisma.client.create({
      data: {
        companyId: companyF.id,
        name: "Davies Family",
        email: "davies@gmail.com",
        phone: "(813) 555-6001",
        address: "801 S Howard Ave",
        city: "Tampa",
        state: "FL",
        zip: "33606",
        notes: "Pool deck resurface.",
      },
    }),
    prisma.client.create({
      data: {
        companyId: companyF.id,
        name: "Coastal Holdings LLC",
        email: "cfo@coastalfl.com",
        phone: "(813) 555-6002",
        address: "1200 Bayshore Blvd",
        city: "Tampa",
        state: "FL",
        zip: "33606",
        notes: "Investor flip portfolio.",
      },
    }),
  ]);

  console.log("  Trade-specialty projects...");

  const projectVerdant1 = await prisma.project.create({
    data: {
      companyId: companyC.id,
      clientId: clientsC[1].id,
      title: "Bergstrom Front Yard Install",
      description: "Boulder + grass border, perennials, drip irrigation.",
      projectType: ProjectType.LANDSCAPING,
      status: ProjectStatus.ESTIMATE_CREATED,
      qualityTier: QualityTier.PREMIUM,
      budgetMin: 8000,
      budgetMax: 14000,
      squareFootage: 1100,
      lawnAreaSqFt: 1100,
      propertyLatitude: 44.9213,
      propertyLongitude: -93.3266,
      createdAt: daysAgo(11),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyC.id,
      clientId: clientsC[2].id,
      title: "Maple Grove Office Entry",
      description: "Entry circle replant. Boxwood + ornamental grasses.",
      projectType: ProjectType.LANDSCAPING,
      status: ProjectStatus.GENERATION_COMPLETE,
      qualityTier: QualityTier.PREMIUM,
      squareFootage: 600,
      lawnAreaSqFt: 600,
      propertyLatitude: 45.0723,
      propertyLongitude: -93.4554,
      createdAt: daysAgo(6),
    },
  });

  const projectVerdantHOA = await prisma.project.create({
    data: {
      companyId: companyC.id,
      clientId: clientsC[0].id,
      title: "Lakeside HOA Common-Area Maintenance",
      description: "Weekly mow, edge, blow. Spring + fall cleanups.",
      projectType: ProjectType.LAWN_CARE,
      status: ProjectStatus.PROPOSAL_SENT,
      qualityTier: QualityTier.PREMIUM,
      lawnAreaSqFt: 174240,
      propertyLatitude: 44.945,
      propertyLongitude: -93.3128,
      isRecurring: true,
      recurrenceFrequency: "weekly",
      visitsPerMonth: 4,
      contractMonths: 7,
      recurrenceStartDate: daysFromNow(14),
      createdAt: daysAgo(10),
    },
  });

  const projectGreensweepHOA = await prisma.project.create({
    data: {
      companyId: companyD.id,
      clientId: clientsD[0].id,
      title: "Sun Valley HOA Year-Round Maintenance",
      description:
        "AZ schedule. Bi-weekly mow, monthly winter, pre-emergent rounds.",
      projectType: ProjectType.LAWN_CARE,
      status: ProjectStatus.APPROVED,
      qualityTier: QualityTier.STANDARD,
      lawnAreaSqFt: 96800,
      propertyLatitude: 33.4944,
      propertyLongitude: -112.0986,
      isRecurring: true,
      recurrenceFrequency: "biweekly",
      visitsPerMonth: 2,
      contractMonths: 12,
      recurrenceStartDate: daysAgo(45),
      createdAt: daysAgo(50),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyD.id,
      clientId: clientsD[1].id,
      title: "Desert Bloom Apartments Mow Route",
      description: "Bi-weekly mow + edge across 3 properties.",
      projectType: ProjectType.LAWN_CARE,
      status: ProjectStatus.INVOICED,
      qualityTier: QualityTier.STANDARD,
      lawnAreaSqFt: 38500,
      propertyLatitude: 33.5081,
      propertyLongitude: -112.0153,
      isRecurring: true,
      recurrenceFrequency: "biweekly",
      visitsPerMonth: 2,
      contractMonths: 12,
      recurrenceStartDate: daysAgo(120),
      createdAt: daysAgo(125),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyD.id,
      clientId: clientsD[2].id,
      title: "Camelback Office Plaza Weekly Service",
      description: "Weekly mow + quarterly cleanup.",
      projectType: ProjectType.LAWN_CARE,
      status: ProjectStatus.GENERATION_COMPLETE,
      qualityTier: QualityTier.PREMIUM,
      lawnAreaSqFt: 22500,
      propertyLatitude: 33.5024,
      propertyLongitude: -111.975,
      isRecurring: true,
      recurrenceFrequency: "weekly",
      visitsPerMonth: 4,
      contractMonths: 12,
      recurrenceStartDate: daysFromNow(7),
      createdAt: daysAgo(2),
    },
  });

  const projectCrownGreene = await prisma.project.create({
    data: {
      companyId: companyE.id,
      clientId: clientsE[0].id,
      title: "Greene Storm Damage Roof Replacement",
      description: "Tear-off + re-roof, insurance claim.",
      projectType: ProjectType.ROOFING,
      status: ProjectStatus.ESTIMATE_CREATED,
      qualityTier: QualityTier.STANDARD,
      squareFootage: 2400,
      roofAreaSqFt: 2680,
      propertyLatitude: 33.8232,
      propertyLongitude: -84.3702,
      createdAt: daysAgo(7),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyE.id,
      clientId: clientsE[1].id,
      title: "Whitfield Premium Architectural Shingles",
      description: "GAF Timberline HDZ Charcoal, ridge vent install.",
      projectType: ProjectType.ROOFING,
      status: ProjectStatus.PROPOSAL_SENT,
      qualityTier: QualityTier.PREMIUM,
      squareFootage: 3100,
      roofAreaSqFt: 3260,
      propertyLatitude: 33.883,
      propertyLongitude: -84.392,
      createdAt: daysAgo(15),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyE.id,
      clientId: clientsE[2].id,
      title: "Brookhaven Townhomes Multi-Building Roof",
      description: "8-building roof replacement. Phased schedule.",
      projectType: ProjectType.ROOFING,
      status: ProjectStatus.DRAFT,
      qualityTier: QualityTier.STANDARD,
      squareFootage: 18800,
      roofAreaSqFt: 18800,
      propertyLatitude: 33.8651,
      propertyLongitude: -84.3375,
      createdAt: daysAgo(3),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyF.id,
      clientId: clientsF[0].id,
      title: "Davies Pool Deck Resurface",
      description: "Travertine paver overlay + lanai screening.",
      projectType: ProjectType.EXTERIOR,
      status: ProjectStatus.ESTIMATE_CREATED,
      qualityTier: QualityTier.PREMIUM,
      squareFootage: 920,
      propertyLatitude: 27.9388,
      propertyLongitude: -82.463,
      createdAt: daysAgo(9),
    },
  });

  await prisma.project.create({
    data: {
      companyId: companyF.id,
      clientId: clientsF[1].id,
      title: "Coastal Flip — South Tampa Bungalow",
      description: "Cosmetic flip: paint, flooring, trim, fixtures.",
      projectType: ProjectType.ROOM_REMODEL,
      status: ProjectStatus.GENERATION_COMPLETE,
      qualityTier: QualityTier.STANDARD,
      squareFootage: 1450,
      propertyLatitude: 27.942,
      propertyLongitude: -82.4595,
      createdAt: daysAgo(4),
    },
  });

  console.log("  Trade-specialty AI generations + materials...");

  const genVerdant1 = await prisma.aIGeneration.create({
    data: {
      projectId: projectVerdant1.id,
      prompt:
        "Front yard install with boulder border, ornamental grasses, drifts of perennials",
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 32100,
      createdAt: daysAgo(10),
    },
  });
  await prisma.materialSuggestion.createMany({
    data: [
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: "Northwind Switchgrass 3 gal",
        category: "Plants",
        estimatedCost: 36,
        unit: "each",
        quantity: 14,
        supplierName: "SiteOne Landscape Supply",
        supplierSearchQuery: "Northwind Switchgrass 3 gallon",
        isSelected: true,
        sortOrder: 0,
      },
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: "Limelight Hydrangea Standard 7 gal",
        category: "Plants",
        estimatedCost: 95,
        unit: "each",
        quantity: 4,
        supplierName: "SiteOne Landscape Supply",
        supplierSearchQuery: "Limelight Hydrangea standard 7 gallon",
        isSelected: true,
        sortOrder: 1,
      },
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: 'Pink Granite Boulder ~36"',
        category: "Stone & Boulders",
        estimatedCost: 220,
        unit: "each",
        quantity: 5,
        supplierName: "Local Stone Yard",
        supplierSearchQuery: "pink granite landscape boulder 36 inch",
        isSelected: true,
        sortOrder: 2,
      },
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: "Cocoa Brown Hardwood Mulch",
        category: "Mulch",
        estimatedCost: 52,
        unit: "cubic_yard",
        quantity: 11,
        supplierName: "SiteOne Landscape Supply",
        supplierSearchQuery: "cocoa brown hardwood mulch bulk",
        isSelected: true,
        sortOrder: 3,
      },
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: "Rain Bird XF Drip Tubing 100 ft",
        category: "Irrigation",
        estimatedCost: 78,
        unit: "roll",
        quantity: 3,
        supplierName: "SiteOne Landscape Supply",
        supplierSearchQuery: "Rain Bird XF dripline 100 ft",
        isSelected: true,
        sortOrder: 4,
      },
      {
        generationId: genVerdant1.id,
        projectId: projectVerdant1.id,
        name: "Miscellaneous Supplies",
        category: "Other",
        estimatedCost: 180,
        unit: "each",
        quantity: 1,
        supplierName: "Home Depot",
        supplierSearchQuery: "landscape installation supplies",
        isSelected: true,
        sortOrder: 5,
      },
    ],
  });

  const genCrown1 = await prisma.aIGeneration.create({
    data: {
      projectId: projectCrownGreene.id,
      prompt:
        "Tear-off + re-roof, GAF Timberline HDZ Pewter Gray, ice and water shield, ridge vent",
      status: GenerationStatus.COMPLETED,
      generationDurationMs: 36800,
      createdAt: daysAgo(6),
    },
  });
  await prisma.materialSuggestion.createMany({
    data: [
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "GAF Timberline HDZ Pewter Gray",
        category: "Roofing",
        estimatedCost: 42,
        unit: "bundle",
        quantity: 90,
        supplierName: "ABC Supply",
        supplierSearchQuery: "GAF Timberline HDZ Pewter Gray bundle",
        isSelected: true,
        sortOrder: 0,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "Synthetic Underlayment 4 sq",
        category: "Underlayment",
        estimatedCost: 110,
        unit: "roll",
        quantity: 7,
        supplierName: "ABC Supply",
        supplierSearchQuery: "synthetic roof underlayment 4 square",
        isSelected: true,
        sortOrder: 1,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "Ice & Water Shield 200 sf",
        category: "Underlayment",
        estimatedCost: 95,
        unit: "roll",
        quantity: 4,
        supplierName: "Home Depot",
        supplierSearchQuery: "ice and water shield 200 sq ft",
        isSelected: true,
        sortOrder: 2,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "Galvanized Drip Edge 10 ft",
        category: "Flashing",
        estimatedCost: 13,
        unit: "each",
        quantity: 36,
        supplierName: "ABC Supply",
        supplierSearchQuery: "galvanized drip edge 10 ft",
        isSelected: true,
        sortOrder: 3,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "GAF Cobra II Ridge Vent 4 ft",
        category: "Ventilation",
        estimatedCost: 11,
        unit: "each",
        quantity: 14,
        supplierName: "Home Depot",
        supplierSearchQuery: "GAF Cobra II ridge vent 4 ft",
        isSelected: true,
        sortOrder: 4,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "30 yd Tear-off Dumpster",
        category: "Disposal",
        estimatedCost: 575,
        unit: "each",
        quantity: 1,
        supplierName: "Local Hauler",
        supplierSearchQuery: "30 yard dumpster roofing",
        isSelected: true,
        sortOrder: 5,
      },
      {
        generationId: genCrown1.id,
        projectId: projectCrownGreene.id,
        name: "Miscellaneous Supplies",
        category: "Other",
        estimatedCost: 240,
        unit: "each",
        quantity: 1,
        supplierName: "Home Depot",
        supplierSearchQuery: "roofing fasteners caulk",
        isSelected: true,
        sortOrder: 6,
      },
    ],
  });

  console.log("  Trade-specialty estimates...");

  await prisma.estimate.create({
    data: {
      projectId: projectVerdant1.id,
      companyId: companyC.id,
      estimateNumber: "VRD-4001",
      title: "Bergstrom Front Yard Install",
      status: EstimateStatus.SENT,
      createdByUserId: liam.id,
      subtotalMaterials: 4720,
      subtotalLabor: 5400,
      taxAmount: 324.5,
      totalAmount: 10444.5,
      validUntil: daysFromNow(21),
      createdAt: daysAgo(10),
    },
  });

  await prisma.estimate.create({
    data: {
      projectId: projectVerdantHOA.id,
      companyId: companyC.id,
      estimateNumber: "VRD-4002",
      title: "Lakeside HOA Common-Area — Per Visit",
      status: EstimateStatus.SENT,
      createdByUserId: liam.id,
      subtotalMaterials: 65,
      subtotalLabor: 425,
      taxAmount: 4.47,
      totalAmount: 494.47,
      assumptions: "Recurring weekly visit. 28 visits over 7 months.",
      validUntil: daysFromNow(30),
      createdAt: daysAgo(9),
    },
  });

  await prisma.estimate.create({
    data: {
      projectId: projectGreensweepHOA.id,
      companyId: companyD.id,
      estimateNumber: "GSW-12001",
      title: "Sun Valley HOA — Per Visit",
      status: EstimateStatus.APPROVED,
      createdByUserId: marcusC.id,
      subtotalMaterials: 110,
      subtotalLabor: 720,
      taxAmount: 71.38,
      totalAmount: 901.38,
      assumptions: "Bi-weekly visit. 24 visits over 12 months.",
      createdAt: daysAgo(46),
    },
  });

  await prisma.estimate.create({
    data: {
      projectId: projectCrownGreene.id,
      companyId: companyE.id,
      estimateNumber: "CRN-16001",
      title: "Greene Storm Damage Roof Replacement",
      status: EstimateStatus.SENT,
      createdByUserId: william.id,
      subtotalMaterials: 7820,
      subtotalLabor: 4400,
      taxAmount: 1087.58,
      totalAmount: 13307.58,
      assumptions: "Insurance approved scope.",
      createdAt: daysAgo(6),
    },
  });

  console.log("  Trade-specialty pricing profiles + labor rates...");

  for (const c of [companyC, companyD, companyE, companyF]) {
    const profile = await prisma.pricingProfile.create({
      data: {
        companyId: c.id,
        name: "Default",
        defaultMarkupPercent: c.defaultMarkupPercent
          ? Number(c.defaultMarkupPercent)
          : 20,
        contingencyPercent: 10,
        wasteFactor: 5,
        isDefault: true,
      },
    });
    await prisma.laborRateRule.createMany({
      data: [
        {
          pricingProfileId: profile.id,
          category: "General Labor",
          ratePerHour: 40,
          minimumHours: 2,
        },
        {
          pricingProfileId: profile.id,
          category: "Skilled Trade",
          ratePerHour: 60,
          minimumHours: 4,
        },
      ],
    });
  }

  console.log("  Trade-specialty usage events + paywall impressions...");

  await prisma.usageEvent.createMany({
    data: [
      {
        userId: liam.id,
        companyId: companyC.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(10),
      },
      {
        userId: marcusC.id,
        companyId: companyD.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(46),
      },
      {
        userId: william.id,
        companyId: companyE.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(6),
      },
      {
        userId: anthony.id,
        companyId: companyF.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(8),
      },
      {
        userId: aisha.id,
        companyId: companyC.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(4),
      },
      {
        userId: tyler.id,
        companyId: companyD.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(2),
      },
      {
        userId: sophia.id,
        companyId: companyE.id,
        metricCode: UsageMetricCode.QUOTE_EXPORT,
        quantity: 1,
        createdAt: daysAgo(2),
      },
      {
        userId: diana.id,
        companyId: companyD.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(1),
      },
      {
        userId: mariaG.id,
        companyId: companyF.id,
        metricCode: UsageMetricCode.AI_GENERATION,
        quantity: 1,
        createdAt: daysAgo(1),
      },
    ],
  });

  await prisma.paywallImpression.createMany({
    data: [
      {
        userId: aisha.id,
        companyId: companyC.id,
        placement: "GENERATION_LIMIT_HIT",
        action: "DISMISSED",
        createdAt: daysAgo(3),
      },
      {
        userId: jenny.id,
        companyId: companyC.id,
        placement: "INVOICE_LOCKED",
        action: "DISMISSED",
        createdAt: daysAgo(1),
      },
      {
        userId: tyler.id,
        companyId: companyD.id,
        placement: "POST_FIRST_GENERATION",
        action: "DISMISSED",
        createdAt: daysAgo(2),
      },
      {
        userId: brittany.id,
        companyId: companyD.id,
        placement: "BRANDING_LOCKED",
        action: "DISMISSED",
        createdAt: daysAgo(5),
      },
      {
        userId: marcusL.id,
        companyId: companyE.id,
        placement: "GENERATION_LIMIT_HIT",
        action: "DISMISSED",
        createdAt: daysAgo(4),
      },
      {
        userId: olivia.id,
        companyId: companyE.id,
        placement: "INVOICE_LOCKED",
        action: "DISMISSED",
        createdAt: daysAgo(6),
      },
      {
        userId: devon.id,
        companyId: companyF.id,
        placement: "ONBOARDING_SOFT_GATE",
        action: "DISMISSED",
        createdAt: daysAgo(2),
      },
      {
        userId: mariaG.id,
        companyId: companyF.id,
        placement: "ONBOARDING_SOFT_GATE",
        action: "STARTED_TRIAL",
        createdAt: daysAgo(2),
      },
    ],
  });

  console.log("  Trade-specialty purchase attempts...");

  await prisma.purchaseAttempt.createMany({
    data: [
      {
        userId: liam.id,
        companyId: companyC.id,
        productId: "proestimate.pro.monthly",
        appAccountToken: "seed-token-liam",
      },
      {
        userId: marcusC.id,
        companyId: companyD.id,
        productId: "proestimate.pro.annual",
        appAccountToken: "seed-token-marcusc",
      },
      {
        userId: william.id,
        companyId: companyE.id,
        productId: "proestimate.pro.monthly",
        appAccountToken: "seed-token-william",
      },
      {
        userId: anthony.id,
        companyId: companyF.id,
        productId: "proestimate.pro.annual",
        appAccountToken: "seed-token-anthony",
      },
      {
        userId: diana.id,
        companyId: companyD.id,
        productId: "proestimate.pro.monthly",
        appAccountToken: "seed-token-diana",
      },
      {
        userId: mariaG.id,
        companyId: companyF.id,
        productId: "proestimate.pro.monthly",
        appAccountToken: "seed-token-maria",
      },
    ],
  });

  // Quiet "unused warning" suppressors — referenced for clarity in logs.
  void carlosM;
  void sophia;
  void tyler;
  void brittany;
  void marcusL;
  void olivia;
  void devon;
  void diana;
}
