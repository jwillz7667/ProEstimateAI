import Foundation

/// A premade prompt suggestion shown in the creation flow as a tappable
/// card. Tapping populates the AI generation prompt with `prompt`; the
/// user can layer custom instructions on top in the input field below.
///
/// Each card carries an `imageAssetName` that points at a bespoke style
/// image under `Assets.xcassets/StyleCards/<Category>/`. The carousel
/// renders the image as the card's hero so users see *visual* style
/// direction. The icon is a small accent on top of the photo.
struct PromptCard: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let imageAssetName: String
    let prompt: String
}

extension PromptCard {
    /// Per-category prompt suggestions surfaced in the creation flow.
    /// Returns six cards per category — four canonical styles plus two
    /// expanded options — each with a dedicated photographic hero.
    static func suggestions(for type: Project.ProjectType) -> [PromptCard] {
        switch type {
        case .kitchen:
            return [
                PromptCard(
                    id: "kitchen.farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "White shaker · butcher block · matte black",
                    icon: "sun.max.fill",
                    imageAssetName: "StyleCards/Kitchen/01_modern_farmhouse",
                    prompt: "Modern farmhouse kitchen with white shaker cabinets, butcher block countertops, apron-front sink, matte black hardware, and warm pendant lighting."
                ),
                PromptCard(
                    id: "kitchen.contemporary",
                    title: "Contemporary",
                    subtitle: "Handle-less · waterfall quartz · integrated",
                    icon: "square.stack.3d.up.fill",
                    imageAssetName: "StyleCards/Kitchen/02_contemporary",
                    prompt: "Contemporary minimalist kitchen with handle-less flat-panel cabinets, a waterfall-edge quartz island, integrated appliances, and recessed LED lighting."
                ),
                PromptCard(
                    id: "kitchen.traditional",
                    title: "Traditional",
                    subtitle: "Raised panel · granite · crown molding",
                    icon: "leaf.fill",
                    imageAssetName: "StyleCards/Kitchen/03_traditional",
                    prompt: "Traditional kitchen with raised-panel cherry cabinets, granite countertops, decorative crown molding, ceramic tile backsplash, and a farmhouse-style chandelier."
                ),
                PromptCard(
                    id: "kitchen.industrial",
                    title: "Industrial",
                    subtitle: "Concrete · brick · open shelving",
                    icon: "wrench.and.screwdriver.fill",
                    imageAssetName: "StyleCards/Kitchen/04_industrial",
                    prompt: "Industrial kitchen with concrete countertops, exposed brick accent wall, open metal shelving, stainless steel appliances, and Edison-bulb pendant lighting."
                ),
                PromptCard(
                    id: "kitchen.mediterranean",
                    title: "Mediterranean",
                    subtitle: "Hand-painted tile · arched range · brass",
                    icon: "flame.fill",
                    imageAssetName: "StyleCards/Kitchen/05_mediterranean",
                    prompt: "Mediterranean kitchen with a hand-painted tile backsplash, an arched range alcove, warm plaster walls, brass fixtures, and reclaimed wood beams overhead."
                ),
                PromptCard(
                    id: "kitchen.japandi",
                    title: "Scandi-Japanese",
                    subtitle: "Light oak · matte clay · paper pendant",
                    icon: "leaf.circle.fill",
                    imageAssetName: "StyleCards/Kitchen/06_scandi_japanese",
                    prompt: "Scandi-Japanese kitchen with light oak slab cabinets, matte clay-toned countertops, integrated handles, paper pendant lighting, and a stone-trough sink."
                ),
            ]
        case .bathroom:
            return [
                PromptCard(
                    id: "bath.spa",
                    title: "Spa Retreat",
                    subtitle: "Walk-in shower · freestanding tub · marble",
                    icon: "drop.fill",
                    imageAssetName: "StyleCards/Bathroom/01_spa_retreat",
                    prompt: "Spa-like bathroom with a frameless walk-in shower, freestanding soaking tub, heated marble floors, and warm ambient lighting."
                ),
                PromptCard(
                    id: "bath.minimal",
                    title: "Modern Minimalist",
                    subtitle: "Floating vanity · vessel sink · porcelain",
                    icon: "circle.dotted",
                    imageAssetName: "StyleCards/Bathroom/02_modern_minimalist",
                    prompt: "Modern minimalist bathroom with a floating wood vanity, vessel sink, large-format porcelain tile, brushed nickel fixtures, and backlit mirror."
                ),
                PromptCard(
                    id: "bath.classic",
                    title: "Classic",
                    subtitle: "Subway tile · claw-foot · beadboard",
                    icon: "building.columns.fill",
                    imageAssetName: "StyleCards/Bathroom/03_classic",
                    prompt: "Classic bathroom with white subway tile, a claw-foot tub, beadboard wainscoting, polished chrome fixtures, and a hexagonal mosaic floor."
                ),
                PromptCard(
                    id: "bath.coastal",
                    title: "Coastal",
                    subtitle: "Shiplap · weathered wood · seafoam",
                    icon: "wind",
                    imageAssetName: "StyleCards/Bathroom/04_coastal",
                    prompt: "Coastal bathroom with shiplap walls, a weathered wood vanity, white quartz countertop, seafoam-green accents, and a pebble shower floor."
                ),
                PromptCard(
                    id: "bath.hotel",
                    title: "Hotel Suite",
                    subtitle: "Wet room · book-matched stone · brass",
                    icon: "sparkles",
                    imageAssetName: "StyleCards/Bathroom/05_hotel_suite",
                    prompt: "Five-star hotel-suite bathroom with a wet-room layout, book-matched stone slab walls, brass fixtures, integrated mirror lighting, and a freestanding stone tub."
                ),
                PromptCard(
                    id: "bath.jewelbox",
                    title: "Powder Room Jewel Box",
                    subtitle: "Bold wallpaper · dark vanity · gold",
                    icon: "diamond.fill",
                    imageAssetName: "StyleCards/Bathroom/06_powder_room_jewel_box",
                    prompt: "Jewel-box powder room with bold botanical wallpaper, a dark walnut floating vanity, polished brass fixtures, vessel sink, and a gold-framed mirror."
                ),
            ]
        case .flooring:
            return [
                PromptCard(
                    id: "floor.hardwood",
                    title: "Wide-Plank Hardwood",
                    subtitle: "Engineered oak · matte · wire-brushed",
                    icon: "rectangle.stack.fill",
                    imageAssetName: "StyleCards/Flooring/01_wide_plank_hardwood",
                    prompt: "Wide-plank engineered hardwood flooring in warm matte oak with a subtle wire-brushed texture, installed throughout the space."
                ),
                PromptCard(
                    id: "floor.concrete",
                    title: "Polished Concrete",
                    subtitle: "Modern · light gray · subtle aggregate",
                    icon: "square.fill",
                    imageAssetName: "StyleCards/Flooring/02_polished_concrete",
                    prompt: "Polished concrete flooring with a clean modern finish, light gray with subtle aggregate, sealed to a satin sheen."
                ),
                PromptCard(
                    id: "floor.lvp",
                    title: "Luxury Vinyl Plank",
                    subtitle: "Realistic oak grain · scratch-resistant",
                    icon: "rectangle.grid.3x2.fill",
                    imageAssetName: "StyleCards/Flooring/03_luxury_vinyl_plank",
                    prompt: "Luxury vinyl plank flooring with realistic oak grain, scratch-resistant wear layer, and beveled edges for a true wood look."
                ),
                PromptCard(
                    id: "floor.tile",
                    title: "Porcelain Tile",
                    subtitle: "Stone-look · large format · light gray",
                    icon: "square.grid.2x2.fill",
                    imageAssetName: "StyleCards/Flooring/04_porcelain_tile",
                    prompt: "Large-format porcelain tile in a stone-look finish, light gray with subtle veining, set with minimal grout lines."
                ),
                PromptCard(
                    id: "floor.herringbone",
                    title: "Herringbone Wood",
                    subtitle: "European oak · chevron · wide",
                    icon: "rectangle.split.3x1",
                    imageAssetName: "StyleCards/Flooring/05_herringbone_wood",
                    prompt: "European white-oak herringbone flooring in a wide-plank chevron pattern, finished with a low-sheen hardwax oil for warm depth."
                ),
                PromptCard(
                    id: "floor.stone",
                    title: "Natural Stone",
                    subtitle: "Travertine · honed · ledger pattern",
                    icon: "circle.hexagongrid.fill",
                    imageAssetName: "StyleCards/Flooring/06_natural_stone",
                    prompt: "Honed travertine flooring in a French ledger pattern with sealed grout, suitable for high-traffic foyers and great rooms."
                ),
            ]
        case .roofing:
            return [
                PromptCard(
                    id: "roof.architectural",
                    title: "Architectural Shingle",
                    subtitle: "Dimensional · charcoal · 30-year",
                    icon: "house.fill",
                    imageAssetName: "StyleCards/Roofing/01_architectural_shingle",
                    prompt: "New architectural asphalt shingle roof in dimensional charcoal, with matching ridge caps and clean drip edge detailing."
                ),
                PromptCard(
                    id: "roof.metal",
                    title: "Standing Seam Metal",
                    subtitle: "Galvalume · clean lines · modern",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "StyleCards/Roofing/02_standing_seam_metal",
                    prompt: "Standing-seam metal roof in galvalume finish with crisp ridge lines, integrated snow guards, and matching trim."
                ),
                PromptCard(
                    id: "roof.tile",
                    title: "Clay Tile",
                    subtitle: "Spanish · terra cotta · classic",
                    icon: "circle.grid.3x3.fill",
                    imageAssetName: "StyleCards/Roofing/03_clay_tile",
                    prompt: "Spanish-style clay tile roof in natural terra cotta, with rounded barrel tiles and decorative ridge caps."
                ),
                PromptCard(
                    id: "roof.slate",
                    title: "Synthetic Slate",
                    subtitle: "Composite · gray · long-lasting",
                    icon: "square.stack.fill",
                    imageAssetName: "StyleCards/Roofing/04_synthetic_slate",
                    prompt: "Synthetic slate roof in graduated gray tones, with copper flashing details and a clean, refined appearance."
                ),
                PromptCard(
                    id: "roof.cedar",
                    title: "Cedar Shake",
                    subtitle: "Hand-split · stained · craftsman",
                    icon: "leaf.fill",
                    imageAssetName: "StyleCards/Roofing/05_cedar_shake",
                    prompt: "Hand-split cedar shake roof with a UV-protective stain, copper valleys, and decorative ridge caps for a craftsman look."
                ),
                PromptCard(
                    id: "roof.coolroof",
                    title: "Cool Roof Coating",
                    subtitle: "Reflective · light gray · energy",
                    icon: "sun.max.circle.fill",
                    imageAssetName: "StyleCards/Roofing/06_cool_roof_coating",
                    prompt: "Reflective cool-roof coating in light gray applied over an existing flat or low-slope roof, reducing cooling load and extending substrate life."
                ),
            ]
        case .painting:
            return [
                PromptCard(
                    id: "paint.warm-neutral",
                    title: "Warm Neutral",
                    subtitle: "Greige · cream trim · cozy",
                    icon: "paintbrush.fill",
                    imageAssetName: "StyleCards/Painting/01_warm_neutral",
                    prompt: "Walls in a warm greige neutral with crisp cream trim and ceiling, creating a cozy and timeless palette."
                ),
                PromptCard(
                    id: "paint.modern",
                    title: "Modern Cool",
                    subtitle: "Soft white · charcoal trim · airy",
                    icon: "circle.lefthalf.filled",
                    imageAssetName: "StyleCards/Painting/02_modern_cool",
                    prompt: "Walls in soft modern white with charcoal accent trim, providing a clean and airy contemporary look."
                ),
                PromptCard(
                    id: "paint.bold",
                    title: "Bold Accent",
                    subtitle: "Deep navy feature · white trim",
                    icon: "sparkle",
                    imageAssetName: "StyleCards/Painting/03_bold_accent",
                    prompt: "Deep navy blue accent wall with the remaining walls in soft white, complemented by bright white trim."
                ),
                PromptCard(
                    id: "paint.exterior",
                    title: "Exterior Refresh",
                    subtitle: "Body · trim · accent color combo",
                    icon: "house.lodge.fill",
                    imageAssetName: "StyleCards/Painting/04_exterior_refresh",
                    prompt: "Fresh exterior paint with a thoughtful three-color combination — body, trim, and front door accent — that elevates curb appeal."
                ),
                PromptCard(
                    id: "paint.limewash",
                    title: "Limewash Walls",
                    subtitle: "Mineral · soft mottling · old-world",
                    icon: "cloud.fill",
                    imageAssetName: "StyleCards/Painting/05_limewash_walls",
                    prompt: "Mineral limewash treatment on walls in a soft warm white with subtle cloud-like mottling for an old-world plaster effect."
                ),
                PromptCard(
                    id: "paint.cabinets",
                    title: "Two-Tone Cabinetry",
                    subtitle: "Sage uppers · cream lowers · matte",
                    icon: "rectangle.split.2x1.fill",
                    imageAssetName: "StyleCards/Painting/06_two_tone_cabinetry",
                    prompt: "Two-tone cabinetry refinish with sage-green uppers and cream lowers in a matte enamel, brushed brass hardware, and freshly painted ceiling."
                ),
            ]
        case .siding:
            return [
                PromptCard(
                    id: "siding.fiber",
                    title: "Fiber Cement",
                    subtitle: "Lap · soft white · architectural trim",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "StyleCards/Siding/01_fiber_cement",
                    prompt: "Fiber cement lap siding in soft white with architectural trim and corner boards, replacing aging existing siding."
                ),
                PromptCard(
                    id: "siding.vinyl",
                    title: "Vinyl Premium",
                    subtitle: "Insulated · low-maintenance",
                    icon: "shield.lefthalf.filled",
                    imageAssetName: "StyleCards/Siding/02_vinyl_premium",
                    prompt: "Premium insulated vinyl siding in a warm tan, with matching soffit, fascia, and seamless gutters."
                ),
                PromptCard(
                    id: "siding.cedar",
                    title: "Cedar Shake",
                    subtitle: "Stained · natural · craftsman",
                    icon: "leaf.fill",
                    imageAssetName: "StyleCards/Siding/03_cedar_shake",
                    prompt: "Cedar shake siding with a transparent stain showing natural grain, accented with stone veneer at the foundation."
                ),
                PromptCard(
                    id: "siding.modern",
                    title: "Modern Mixed",
                    subtitle: "Vertical board & batten · stone",
                    icon: "square.split.2x1.fill",
                    imageAssetName: "StyleCards/Siding/04_modern_mixed",
                    prompt: "Modern mixed siding combining vertical board-and-batten with horizontal lap accents and a stone veneer base."
                ),
                PromptCard(
                    id: "siding.blackvert",
                    title: "Black Modern Vertical",
                    subtitle: "Charred wood · vertical · bold",
                    icon: "square.split.bottomrightquarter.fill",
                    imageAssetName: "StyleCards/Siding/05_black_modern_vertical",
                    prompt: "Charred-wood-look vertical siding in deep black with crisp shadow lines, paired with bronze window frames and a natural stone base."
                ),
                PromptCard(
                    id: "siding.stucco",
                    title: "Stucco & Stone",
                    subtitle: "Smooth stucco · stacked stone · warm",
                    icon: "circle.grid.cross.fill",
                    imageAssetName: "StyleCards/Siding/06_stucco_and_stone",
                    prompt: "Smooth integral-color stucco with stacked-stone wainscoting, painted wood trim, and a warm desert palette."
                ),
            ]
        case .roomRemodel:
            return [
                PromptCard(
                    id: "room.modern",
                    title: "Modern",
                    subtitle: "Clean lines · neutral palette · light",
                    icon: "square.dashed",
                    imageAssetName: "StyleCards/RoomRemodel/01_modern",
                    prompt: "Modern room with clean architectural lines, a soft neutral palette, hardwood floors, and abundant natural light."
                ),
                PromptCard(
                    id: "room.transitional",
                    title: "Transitional",
                    subtitle: "Mix of classic & contemporary",
                    icon: "arrow.triangle.merge",
                    imageAssetName: "StyleCards/RoomRemodel/02_transitional",
                    prompt: "Transitional space blending classic millwork with contemporary furnishings, layered textures, and warm wood tones."
                ),
                PromptCard(
                    id: "room.scandinavian",
                    title: "Scandinavian",
                    subtitle: "Light wood · white · cozy textiles",
                    icon: "snowflake",
                    imageAssetName: "StyleCards/RoomRemodel/03_scandinavian",
                    prompt: "Scandinavian room with light oak floors, white walls, simple furniture, and cozy textiles for warmth."
                ),
                PromptCard(
                    id: "room.industrial",
                    title: "Industrial",
                    subtitle: "Exposed brick · metal · vintage",
                    icon: "gearshape.2.fill",
                    imageAssetName: "StyleCards/RoomRemodel/04_industrial",
                    prompt: "Industrial-leaning room with exposed brick, blackened steel accents, vintage furniture, and Edison-bulb fixtures."
                ),
                PromptCard(
                    id: "room.midcentury",
                    title: "Mid-Century Modern",
                    subtitle: "Walnut · low profile · warm tones",
                    icon: "sun.haze.fill",
                    imageAssetName: "StyleCards/RoomRemodel/05_mid_century_modern",
                    prompt: "Mid-century modern room with walnut paneling, low-profile furniture, mustard and teal accents, and a sunburst-style fixture."
                ),
                PromptCard(
                    id: "room.boho",
                    title: "Boho Layered",
                    subtitle: "Rattan · macramé · plants",
                    icon: "leaf.circle.fill",
                    imageAssetName: "StyleCards/RoomRemodel/06_boho_layered",
                    prompt: "Bohemian layered room with rattan furniture, macramé textiles, vintage rugs, abundant plants, and warm filament lighting."
                ),
            ]
        case .exterior:
            return [
                PromptCard(
                    id: "exterior.modern",
                    title: "Modern Refresh",
                    subtitle: "Clean lines · bold front door",
                    icon: "house.fill",
                    imageAssetName: "StyleCards/Exterior/01_modern_refresh",
                    prompt: "Modern exterior refresh with crisp white siding, a bold black front door, minimalist landscape lighting, and architectural house numbers."
                ),
                PromptCard(
                    id: "exterior.craftsman",
                    title: "Craftsman",
                    subtitle: "Cedar accents · stone base · pillars",
                    icon: "tree.fill",
                    imageAssetName: "StyleCards/Exterior/02_craftsman",
                    prompt: "Craftsman-style exterior with stained cedar accents, a stone veneer base, tapered porch pillars, and warm exterior lighting."
                ),
                PromptCard(
                    id: "exterior.modern-farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "Board & batten · black accents",
                    icon: "house.lodge.fill",
                    imageAssetName: "StyleCards/Exterior/03_modern_farmhouse",
                    prompt: "Modern farmhouse exterior with white board-and-batten siding, black window frames, metal roof accents, and a covered front porch."
                ),
                PromptCard(
                    id: "exterior.coastal",
                    title: "Coastal",
                    subtitle: "Shingle · soft blue · weathered",
                    icon: "wind",
                    imageAssetName: "StyleCards/Exterior/04_coastal",
                    prompt: "Coastal exterior with cedar shingle siding weathered to a silver patina, soft blue trim, and a welcoming front porch."
                ),
                PromptCard(
                    id: "exterior.midcentury",
                    title: "Mid-Century Ranch",
                    subtitle: "Low-slope · wood beams · planters",
                    icon: "rectangle.3.offgrid.fill",
                    imageAssetName: "StyleCards/Exterior/05_mid_century_ranch",
                    prompt: "Mid-century ranch exterior with a low-slope roofline, exposed wood beams, vertical wood siding, integrated planters, and globe sconces."
                ),
                PromptCard(
                    id: "exterior.mediterranean",
                    title: "Mediterranean",
                    subtitle: "Stucco · terra cotta · arches",
                    icon: "sun.max.fill",
                    imageAssetName: "StyleCards/Exterior/06_mediterranean",
                    prompt: "Mediterranean exterior with smooth white stucco walls, a terra-cotta tile roof, arched entryways, wrought-iron lanterns, and tiled accents."
                ),
            ]
        case .landscaping:
            return [
                PromptCard(
                    id: "land.modern",
                    title: "Modern Minimalist",
                    subtitle: "Clean planting beds · gravel · steel",
                    icon: "rectangle.3.offgrid.fill",
                    imageAssetName: "StyleCards/Landscaping/01_modern_minimalist",
                    prompt: "Modern minimalist landscape with clean rectangular planting beds, ornamental grasses, decorative gravel, and corten steel edging."
                ),
                PromptCard(
                    id: "land.cottage",
                    title: "Cottage Garden",
                    subtitle: "Layered perennials · flagstone path",
                    icon: "leaf.fill",
                    imageAssetName: "StyleCards/Landscaping/02_cottage_garden",
                    prompt: "Cottage-style garden with layered perennials, a winding flagstone path, climbing roses, and a small seating nook."
                ),
                PromptCard(
                    id: "land.xeriscape",
                    title: "Drought-Tolerant",
                    subtitle: "Native plants · mulch · efficient",
                    icon: "drop.degreesign.slash",
                    imageAssetName: "StyleCards/Landscaping/03_drought_tolerant",
                    prompt: "Drought-tolerant xeriscape with native grasses, succulents, decorative boulders, and efficient drip irrigation."
                ),
                PromptCard(
                    id: "land.entertaining",
                    title: "Outdoor Living",
                    subtitle: "Patio · firepit · pergola",
                    icon: "flame.fill",
                    imageAssetName: "StyleCards/Landscaping/04_outdoor_living",
                    prompt: "Outdoor living landscape featuring a paver patio, gas firepit with seating, cedar pergola, and ambient string lighting."
                ),
                PromptCard(
                    id: "land.zen",
                    title: "Japanese Zen",
                    subtitle: "Raked gravel · Japanese maples · stone",
                    icon: "circle.hexagonpath.fill",
                    imageAssetName: "StyleCards/Landscaping/05_japanese_zen",
                    prompt: "Japanese zen garden with raked gravel beds, sculptural Japanese maples, basalt stepping stones, a stone water basin, and clipped boxwood."
                ),
                PromptCard(
                    id: "land.edible",
                    title: "Edible Garden",
                    subtitle: "Raised cedar beds · espalier · paths",
                    icon: "carrot.fill",
                    imageAssetName: "StyleCards/Landscaping/06_edible_garden",
                    prompt: "Edible garden with cedar raised beds, espaliered fruit trees, pollinator borders, gravel paths, and a compact greenhouse."
                ),
            ]
        case .lawnCare:
            return [
                PromptCard(
                    id: "lawn.weekly",
                    title: "Weekly Maintenance",
                    subtitle: "Mow · edge · blow · trim",
                    icon: "leaf.fill",
                    imageAssetName: "StyleCards/LawnCare/01_weekly_maintenance",
                    prompt: "Recurring weekly lawn maintenance: precision mowing, hard-edge work, debris blowing, and periodic shrub trimming."
                ),
                PromptCard(
                    id: "lawn.fert",
                    title: "Fertilization Program",
                    subtitle: "Multi-step · seasonal · weed control",
                    icon: "drop.fill",
                    imageAssetName: "StyleCards/LawnCare/02_fertilization_program",
                    prompt: "Multi-step seasonal fertilization program with pre-emergent weed control, targeted nutrients, and broadleaf treatments."
                ),
                PromptCard(
                    id: "lawn.aeration",
                    title: "Aeration & Overseed",
                    subtitle: "Core aerate · top-quality seed",
                    icon: "circle.grid.cross.fill",
                    imageAssetName: "StyleCards/LawnCare/03_aeration_overseed",
                    prompt: "Annual core aeration with overseed using top-quality cool-season turf blend, topdressed for healthy establishment."
                ),
                PromptCard(
                    id: "lawn.cleanup",
                    title: "Spring/Fall Cleanup",
                    subtitle: "Bed clearing · leaves · trim back",
                    icon: "wind",
                    imageAssetName: "StyleCards/LawnCare/04_spring_fall_cleanup",
                    prompt: "Comprehensive spring or fall cleanup: bed clearing, leaf removal, hard prune of shrubs, and fresh edging."
                ),
                PromptCard(
                    id: "lawn.petsafe",
                    title: "Pet-Safe Treatments",
                    subtitle: "Organic · low-toxicity · family",
                    icon: "pawprint.fill",
                    imageAssetName: "StyleCards/LawnCare/05_pet_safe_treatments",
                    prompt: "Pet- and child-safe lawn program using organic fertilizers, low-toxicity weed control, and selective spot treatments."
                ),
                PromptCard(
                    id: "lawn.sod",
                    title: "Sod & Renovation",
                    subtitle: "Strip · grade · install · roll",
                    icon: "rectangle.roundedtop.fill",
                    imageAssetName: "StyleCards/LawnCare/06_sod_renovation",
                    prompt: "Full lawn renovation: strip existing turf, regrade and amend topsoil, install premium sod, and roll for tight seam contact."
                ),
            ]
        case .outdoorLiving:
            return [
                PromptCard(
                    id: "outdoor.patio",
                    title: "Paver Patio",
                    subtitle: "Flagstone · pergola · seating",
                    icon: "square.grid.2x2.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/01_paver_patio",
                    prompt: "Refined paver patio with flagstone borders, a covered pergola overhead, built-in bench seating, and ambient string lighting."
                ),
                PromptCard(
                    id: "outdoor.kitchen",
                    title: "Outdoor Kitchen",
                    subtitle: "Built-in grill · stone counter · bar",
                    icon: "flame.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/02_outdoor_kitchen",
                    prompt: "Outdoor kitchen with a built-in stainless grill, stone-clad counter, side burner, integrated refrigerator, and a covered bar with stools."
                ),
                PromptCard(
                    id: "outdoor.pergola",
                    title: "Pergola & Shade",
                    subtitle: "Cedar beams · slatted top · vines",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/03_pergola_shade",
                    prompt: "Cedar pergola with slatted top, climbing vines, retractable shade cloth, and integrated downlighting for evening use."
                ),
                PromptCard(
                    id: "outdoor.firepit",
                    title: "Firepit Lounge",
                    subtitle: "Gas firepit · stone surround · cozy",
                    icon: "flame.circle.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/04_firepit_lounge",
                    prompt: "Gas firepit lounge with a circular stone surround, weather-resistant lounge seating, and a paver landing with low landscape lighting."
                ),
                PromptCard(
                    id: "outdoor.hottub",
                    title: "Hot Tub Deck",
                    subtitle: "Recessed · screened privacy · wood",
                    icon: "drop.circle.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/05_hot_tub_deck",
                    prompt: "Outdoor living deck with a recessed hot tub, cedar privacy screens, integrated bench seating, and warm step lighting."
                ),
                PromptCard(
                    id: "outdoor.screened",
                    title: "Screened Porch",
                    subtitle: "All-season · ceiling fan · fireplace",
                    icon: "fan.fill",
                    imageAssetName: "StyleCards/OutdoorLiving/06_screened_porch",
                    prompt: "Screened porch with floor-to-ceiling screens, vaulted ceiling with fan, stone fireplace, and weather-resistant lounge furniture for three-season comfort."
                ),
            ]
        case .garage:
            return [
                PromptCard(
                    id: "garage.workshop",
                    title: "Workshop Fit-Out",
                    subtitle: "Wall-to-wall benches · pegboard · LED",
                    icon: "wrench.and.screwdriver.fill",
                    imageAssetName: "StyleCards/Garage/01_workshop_fit_out",
                    prompt: "Garage workshop fit-out with wall-to-wall hardwood workbenches, pegboard tool storage, slatwall accessories, epoxy floor coating, and bright LED panel lighting."
                ),
                PromptCard(
                    id: "garage.ev",
                    title: "EV-Ready Bay",
                    subtitle: "Level 2 charger · sealed floor · clean",
                    icon: "bolt.car.fill",
                    imageAssetName: "StyleCards/Garage/02_ev_ready_bay",
                    prompt: "Modern garage upgrade with a wall-mounted Level 2 EV charger, sealed concrete floor, recessed cable management, motion-activated LEDs, and an insulated overhead door."
                ),
                PromptCard(
                    id: "garage.conversion",
                    title: "Livable Conversion",
                    subtitle: "Office or studio · insulated · finished",
                    icon: "rectangle.3.group.fill",
                    imageAssetName: "StyleCards/Garage/03_livable_conversion",
                    prompt: "Garage converted to a finished livable studio with insulated walls and ceiling, drywall and trim, vinyl plank flooring, mini-split HVAC, and large windows replacing the overhead door."
                ),
                PromptCard(
                    id: "garage.storage",
                    title: "Storage & Organization",
                    subtitle: "Overhead racks · cabinets · ceiling lift",
                    icon: "shippingbox.fill",
                    imageAssetName: "StyleCards/Garage/04_storage_organization",
                    prompt: "Garage storage and organization with overhead ceiling racks, full-height steel cabinetry, slatwall hooks, bicycle and kayak hoists, and a clean labeled-bin system."
                ),
                PromptCard(
                    id: "garage.showroom",
                    title: "Showroom Bay",
                    subtitle: "Tile floor · backlit · glass door",
                    icon: "sparkles",
                    imageAssetName: "StyleCards/Garage/05_showroom_bay",
                    prompt: "Showroom-style garage bay with porcelain tile flooring, backlit slatwall, a glass overhead door, and color-matched cabinetry."
                ),
                PromptCard(
                    id: "garage.gym",
                    title: "Home Gym Conversion",
                    subtitle: "Rubber floor · mirror wall · rack",
                    icon: "figure.strengthtraining.traditional",
                    imageAssetName: "StyleCards/Garage/06_home_gym_conversion",
                    prompt: "Garage-to-home-gym conversion with rubber tile flooring, mirrored accent wall, mounted rack, mini-split HVAC, and bright LED panel lighting."
                ),
            ]
        case .custom:
            return [
                PromptCard(
                    id: "custom.modern",
                    title: "Modern",
                    subtitle: "Clean lines · contemporary materials",
                    icon: "square.dashed",
                    imageAssetName: "StyleCards/Custom/01_modern",
                    prompt: "Modern design with clean lines, contemporary materials, and a thoughtful neutral palette."
                ),
                PromptCard(
                    id: "custom.traditional",
                    title: "Traditional",
                    subtitle: "Classic detailing · warm tones",
                    icon: "building.columns.fill",
                    imageAssetName: "StyleCards/Custom/02_traditional",
                    prompt: "Traditional design with classic detailing, warm wood tones, and timeless finishes."
                ),
                PromptCard(
                    id: "custom.minimal",
                    title: "Minimalist",
                    subtitle: "Spare · refined · light",
                    icon: "circle.dotted",
                    imageAssetName: "StyleCards/Custom/03_minimalist",
                    prompt: "Minimalist design that's spare and refined, with light tones and uncluttered surfaces."
                ),
                PromptCard(
                    id: "custom.bold",
                    title: "Bold Statement",
                    subtitle: "High contrast · dramatic accents",
                    icon: "sparkle",
                    imageAssetName: "StyleCards/Custom/04_bold_statement",
                    prompt: "Bold statement design with high-contrast colors, dramatic accents, and confident material choices."
                ),
                PromptCard(
                    id: "custom.industrial",
                    title: "Industrial Loft",
                    subtitle: "Exposed brick · steel · concrete",
                    icon: "gearshape.2.fill",
                    imageAssetName: "StyleCards/Custom/05_industrial_loft",
                    prompt: "Industrial loft style with exposed brick, blackened-steel detailing, polished concrete, and warm filament lighting."
                ),
                PromptCard(
                    id: "custom.coastal",
                    title: "Coastal Calm",
                    subtitle: "Whitewashed wood · linen · sea glass",
                    icon: "wind",
                    imageAssetName: "StyleCards/Custom/06_coastal_calm",
                    prompt: "Coastal calm style with whitewashed wood, soft linen textures, sea-glass accents, and abundant natural light."
                ),
            ]
        }
    }
}
