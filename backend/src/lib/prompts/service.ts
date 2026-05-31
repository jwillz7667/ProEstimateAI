import { PromptContext } from "./types";
import {
  humanizeType,
  imageFrame,
  laborJsonContract,
  materialJsonContract,
  projectFactsBlock,
  supplierGuidance,
  tierBoundsBlock,
  tierLanguage,
} from "./shared";

/**
 * Home-service trades (PLUMBING, ELECTRICAL, HVAC, APPLIANCE_REPAIR,
 * HANDYMAN, PEST_CONTROL, HOUSE_CLEANING, JUNK_REMOVAL, PRESSURE_WASHING,
 * GUTTER_SERVICES, FENCING, GARAGE_DOOR, WINDOW_CLEANING).
 *
 * Unlike the remodel modules these price a SERVICE CALL — a repair, install,
 * or maintenance visit — where the customer is NOT redesigning anything. So
 * the estimate is dominated by labor + a small parts/consumables list, and
 * these project types default to no AI image (Project.aiPreviewEnabled). The
 * single module handles all 13 trades, differentiating through a per-trade
 * guidance table; the registry routes each enum value here.
 */

// Service-relevant subset of CATEGORY_TIER_BOUNDS. Anything outside these
// (HVAC refrigerant, appliance control boards, pest treatments, cleaning
// chemicals) lands in the "other" catch-all, which clamps loosely.
const SERVICE_CATEGORIES = [
  "plumbing",
  "electrical",
  "fixtures",
  "lighting",
  "hardware",
  "fencing",
  "paint",
  "drywall",
  "fasteners",
  "disposal",
  "other",
];

interface TradeGuide {
  partsGuidance: string;
  laborGuidance: string;
  imageSubject: string;
}

const GENERIC_GUIDE: TradeGuide = {
  partsGuidance:
    "Quote the replacement parts and consumables actually used to complete the described service. Most service calls need only a handful of parts.",
  laborGuidance:
    "Quote on-site labor for the described task. Add a separate trip/diagnostic line when the trade normally charges one.",
  imageSubject:
    "The serviced area after the contractor's described work is complete — clean, finished, fully reassembled.",
};

const TRADE_GUIDES: Record<string, TradeGuide> = {
  PLUMBING: {
    partsGuidance:
      "Supply lines, shutoff/angle-stop valves, P-traps, wax rings, faucet/valve cartridges, PEX/copper/PVC fittings, water-heater components, pipe sections. Price only what the described repair/install consumes.",
    laborGuidance:
      "Diagnostic line + the repair/replacement itself. A typical fixture swap or leak repair is 1–3 hours on site.",
    imageSubject:
      "The repaired or newly installed plumbing fixture (faucet, water heater, toilet, under-sink supply) — clean, dry, leak-free.",
  },
  ELECTRICAL: {
    partsGuidance:
      "Breakers, GFCI/standard outlets, switches, dimmers, wire (by the foot), junction boxes, wire nuts, cover plates, panel components. Quote only the devices the described work requires.",
    laborGuidance:
      "Diagnostic/troubleshoot line + install or repair. A typical device or fixture job is 1–3 hours; panel/sub-panel work runs longer.",
    imageSubject:
      "The completed electrical work (new outlet, light fixture, panel, EV charger) — neat, finished, code-clean.",
  },
  HVAC: {
    partsGuidance:
      "Capacitors, contactors, fan/blower motors, thermostats, filters, refrigerant (by the pound), condensate pump/line parts, igniters, flame sensors. Price the failed component(s) for a repair, or the equipment for a replacement.",
    laborGuidance:
      "Diagnostic line + repair or maintenance. A repair is typically 1–4 hours. For a maintenance plan this is a recurring per-visit tune-up.",
    imageSubject:
      "The serviced HVAC equipment (condenser, furnace, mini-split head, thermostat) — clean and tidy.",
  },
  APPLIANCE_REPAIR: {
    partsGuidance:
      "The specific replacement component for the failure described — heating element, drain/circulation pump, control board, drive belt, door gasket, igniter, valve. Usually 1–3 parts total.",
    laborGuidance:
      "Diagnostic line + the repair. Most appliance repairs are 1–2 hours on site.",
    imageSubject:
      "The repaired appliance — clean, reassembled, and operational in place.",
  },
  HANDYMAN: {
    partsGuidance:
      "Task-specific materials: fasteners, anchors, caulk, patch compound, small hardware, brackets, replacement trim, the fixture being mounted. Group by the tasks in the contractor's notes.",
    laborGuidance:
      "One labor line per distinct task (mount TV, patch drywall, re-caulk tub, hang door). Small tasks are 0.5–2 hours each.",
    imageSubject:
      "The completed handyman tasks — patched, painted, mounted, or repaired — left tidy.",
  },
  PEST_CONTROL: {
    partsGuidance:
      "Treatment consumables: bait stations, gel/granular baits, liquid concentrate (by application), traps, exclusion materials. Mostly consumables, not durable parts.",
    laborGuidance:
      "Inspection + treatment labor per visit. Often a recurring monthly/quarterly contract — quote per visit when recurring.",
    imageSubject:
      "The treated property exterior/interior — clean, with bait stations discreetly placed.",
  },
  HOUSE_CLEANING: {
    partsGuidance:
      "Cleaning supplies and consumables only (solutions, pads, liners, bags). Keep this minimal — labor dominates the bid.",
    laborGuidance:
      "Per-visit cleaning labor scaled to home size (rooms / square footage). Often a recurring weekly/biweekly/monthly contract — quote per visit when recurring.",
    imageSubject:
      "A spotless, freshly cleaned room — gleaming surfaces, vacuumed floor, staged tidy.",
  },
  JUNK_REMOVAL: {
    partsGuidance:
      "Disposal/dump and landfill fees, recycling fees, contractor bags, shrink wrap. The disposal fee is usually the largest non-labor line.",
    laborGuidance:
      "Load-out and haul-away labor, typically priced by truck volume (quarter / half / full load). 1–3 hours per job.",
    imageSubject:
      "The cleared, empty space after haul-away (garage, yard, basement) — swept clean.",
  },
  PRESSURE_WASHING: {
    partsGuidance:
      "Detergents/surfactants, degreaser, sodium hypochlorite for soft-wash, sealer if specified. Consumables priced by the job, not durable parts.",
    laborGuidance:
      "Labor by surface area / surface type (driveway, siding, deck, patio). A typical residential job is 2–5 hours.",
    imageSubject:
      "The freshly pressure-washed surface (driveway, siding, deck) — bright and clean against the surrounding grime line.",
  },
  GUTTER_SERVICES: {
    partsGuidance:
      "For repair/install: K-style gutter sections, downspouts, hangers/hidden brackets, end caps, elbows, gutter guards, seam sealant. For a cleaning, parts are minimal — mostly a misc line.",
    laborGuidance:
      "Clean / repair / install labor by linear footage and stories. A clean is 1–3 hours; a guard install or section replacement runs longer.",
    imageSubject:
      "Clean, properly pitched gutters with downspouts draining clear — straight runs, no debris, no sag.",
  },
  FENCING: {
    partsGuidance:
      "Fence pickets/panels, posts, rails, post concrete, gate kits, hinges, latches, post caps. Price the run by linear foot (the Fencing category) plus gates and hardware as each.",
    laborGuidance:
      "Layout, post setting, panel/picket install, gate hang. A residential run is typically 8–24 hours depending on length and terrain.",
    imageSubject:
      "The completed fence line — straight, plumb posts, even picket spacing, gates hung and aligned.",
  },
  GARAGE_DOOR: {
    partsGuidance:
      "Torsion/extension springs, rollers, cables, hinges, opener unit, drums, weather seal/bottom astragal, panels for a replacement. Price the failed components for a repair.",
    laborGuidance:
      "Diagnostic + repair or full install. A spring/roller repair is 1–2 hours; a full door + opener install runs 3–5 hours.",
    imageSubject:
      "The installed or repaired garage door — closed, aligned in the tracks, panels even.",
  },
  WINDOW_CLEANING: {
    partsGuidance:
      "Cleaning solution, squeegee pads, scrim/microfiber, scraper blades, purified-water consumables. Minimal — labor dominates.",
    laborGuidance:
      "Labor by window count and stories (interior + exterior). A typical home is 2–4 hours. Quote per visit if recurring.",
    imageSubject:
      "Streak-free, crystal-clear windows — clean glass, wiped frames and sills.",
  },
};

function tradeGuide(projectType: string): TradeGuide {
  return TRADE_GUIDES[projectType.toUpperCase()] ?? GENERIC_GUIDE;
}

export function imagePrompt(ctx: PromptContext): string {
  const guide = tradeGuide(ctx.projectType);
  return `
${imageFrame(ctx)}

SUBJECT
${guide.imageSubject}

This is a POST-SERVICE shot — the work described in the contractor's notes
has just been completed. Show the serviced area clean, finished, and fully
reassembled: no tools, no debris, no work-in-progress. Lean on the
contractor's notes to determine the exact subject and framing.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  const guide = tradeGuide(ctx.projectType);

  return `
You are a senior ${humanizeType(ctx.projectType)} service estimator pricing a
SERVICE CALL — a repair, install, or maintenance visit, NOT a remodel. The
customer is not redesigning anything; quote only the parts and consumables
actually used to complete the work described.

${projectFactsBlock(ctx)}

PARTS GUIDANCE
${guide.partsGuidance}
Anchor pricing to ${tier.materialAnchor}

ALLOWED CATEGORIES
Plumbing, Electrical, Fixtures, Lighting, Hardware, Fencing, Paint, Drywall,
Fasteners, Disposal, Other

${tierBoundsBlock(ctx.qualityTier, SERVICE_CATEGORIES)}

SERVICE OVERRIDE — takes precedence over the item-count and Miscellaneous
pricing in the OUTPUT CONTRACT below:
- A service call typically needs only 1–8 parts. Quote ONLY parts genuinely
  required for the described work — do NOT pad the list to hit a count, and
  do NOT invent fixtures the customer didn't ask for.
- Include exactly ONE final "Miscellaneous Supplies" line (sealant, fittings,
  fasteners, wire nuts, blades, rags) priced $20–$150 TOTAL: unit="each",
  quantity=1, estimatedCost between 20 and 150.
- If the job is essentially pure labor with no parts (a diagnostic, a
  cleaning, an inspection, a haul-away), return ONLY that single
  "Miscellaneous Supplies" line.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  const guide = tradeGuide(ctx.projectType);
  const recurring = ctx.isRecurring === true;

  return `
You are a senior ${humanizeType(ctx.projectType)} service estimator producing a
labor schedule for a SERVICE CALL (not a remodel).

${projectFactsBlock(ctx)}

LABOR GUIDANCE
${guide.laborGuidance}
${
  recurring
    ? "This is a RECURRING contract — quote labor PER VISIT only. The orchestrator rolls the per-visit total up to monthly/annual using the visit count above; do NOT multiply by the term yourself."
    : "This is a one-time service call. Most calls are 1–4 hours of on-site labor plus, when the trade normally charges one, a separate trip/diagnostic line."
}

ALLOWED LABOR CATEGORIES
Diagnostic, Service Call, Repair, Installation, Maintenance, Cleanup,
Haul-Away, Inspection, Supervision, General Labor

TIER LABOR RATES: ${tier.pricingMultiplier}. The orchestrator clamps every
ratePerHour to the tier's band — quoting outside will be silently adjusted.

${laborJsonContract()}
`.trim();
}
