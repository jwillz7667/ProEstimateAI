import Foundation

/// A premade prompt suggestion shown in the creation flow as a tappable
/// card. Tapping populates the AI generation prompt with `prompt`; the
/// user can layer custom instructions on top in the input field below.
///
/// Each card carries an `imageAssetName` that points at a curated photo
/// in `Assets.xcassets/CategoryThumbs/`. The carousel renders the image
/// as the card's hero so users see *visual* style direction, not just
/// copy. The icon is retained as a small accent on top of the photo.
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
    /// Always returns four cards so the carousel layout is predictable.
    static func suggestions(for type: Project.ProjectType) -> [PromptCard] {
        switch type {
        case .kitchen:
            // All four cards use kitchen-zone thumbnails (the lone kitchen
            // shot plus the breakfast nook and pantry shots that show
            // cabinetry/countertops in a kitchen context). Style is
            // conveyed through the title, subtitle, and prompt — not the
            // photo, which only signals "this is a kitchen."
            return [
                PromptCard(
                    id: "kitchen.farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "White shaker · butcher block · matte black",
                    icon: "sun.max.fill",
                    imageAssetName: "CategoryThumbs/13_butlers_pantry",
                    prompt: "Modern farmhouse kitchen with white shaker cabinets, butcher block countertops, apron-front sink, matte black hardware, and warm pendant lighting."
                ),
                PromptCard(
                    id: "kitchen.contemporary",
                    title: "Contemporary",
                    subtitle: "Handle-less · waterfall quartz · integrated",
                    icon: "square.stack.3d.up.fill",
                    imageAssetName: "CategoryThumbs/01_modern_kitchen",
                    prompt: "Contemporary minimalist kitchen with handle-less flat-panel cabinets, a waterfall-edge quartz island, integrated appliances, and recessed LED lighting."
                ),
                PromptCard(
                    id: "kitchen.traditional",
                    title: "Traditional",
                    subtitle: "Raised panel · granite · crown molding",
                    icon: "leaf.fill",
                    imageAssetName: "CategoryThumbs/12_breakfast_nook",
                    prompt: "Traditional kitchen with raised-panel cherry cabinets, granite countertops, decorative crown molding, ceramic tile backsplash, and a farmhouse-style chandelier."
                ),
                PromptCard(
                    id: "kitchen.industrial",
                    title: "Industrial",
                    subtitle: "Concrete · brick · open shelving",
                    icon: "wrench.and.screwdriver.fill",
                    imageAssetName: "CategoryThumbs/14_walk_in_pantry",
                    prompt: "Industrial kitchen with concrete countertops, exposed brick accent wall, open metal shelving, stainless steel appliances, and Edison-bulb pendant lighting."
                ),
            ]
        case .bathroom:
            // Two true bathroom shots in the catalog (luxury bath + powder
            // room) plus the sauna which is a wet-space wellness scene
            // honest for "spa retreat." The other two cards reuse the
            // legitimate bathroom thumbnails rather than substituting an
            // unrelated room.
            return [
                PromptCard(
                    id: "bath.spa",
                    title: "Spa Retreat",
                    subtitle: "Walk-in shower · freestanding tub · marble",
                    icon: "drop.fill",
                    imageAssetName: "CategoryThumbs/24_sauna",
                    prompt: "Spa-like bathroom with a frameless walk-in shower, freestanding soaking tub, heated marble floors, and warm ambient lighting."
                ),
                PromptCard(
                    id: "bath.minimal",
                    title: "Modern Minimalist",
                    subtitle: "Floating vanity · vessel sink · porcelain",
                    icon: "circle.dotted",
                    imageAssetName: "CategoryThumbs/02_luxury_bathroom",
                    prompt: "Modern minimalist bathroom with a floating wood vanity, vessel sink, large-format porcelain tile, brushed nickel fixtures, and backlit mirror."
                ),
                PromptCard(
                    id: "bath.classic",
                    title: "Classic",
                    subtitle: "Subway tile · claw-foot · beadboard",
                    icon: "building.columns.fill",
                    imageAssetName: "CategoryThumbs/07_powder_room",
                    prompt: "Classic bathroom with white subway tile, a claw-foot tub, beadboard wainscoting, polished chrome fixtures, and a hexagonal mosaic floor."
                ),
                PromptCard(
                    id: "bath.coastal",
                    title: "Coastal",
                    subtitle: "Shiplap · weathered wood · seafoam",
                    icon: "wind",
                    imageAssetName: "CategoryThumbs/02_luxury_bathroom",
                    prompt: "Coastal bathroom with shiplap walls, a weathered wood vanity, white quartz countertop, seafoam-green accents, and a pebble shower floor."
                ),
            ]
        case .flooring:
            // Flooring is whole-room work — every interior shot has a
            // floor in frame. We pick rooms where the floor genuinely
            // dominates the composition (dining room with wide-plank,
            // entry with tile, living room with LVP, game room with
            // polished concrete).
            return [
                PromptCard(
                    id: "floor.hardwood",
                    title: "Wide-Plank Hardwood",
                    subtitle: "Engineered oak · matte · wire-brushed",
                    icon: "rectangle.stack.fill",
                    imageAssetName: "CategoryThumbs/11_dining_room",
                    prompt: "Wide-plank engineered hardwood flooring in warm matte oak with a subtle wire-brushed texture, installed throughout the space."
                ),
                PromptCard(
                    id: "floor.concrete",
                    title: "Polished Concrete",
                    subtitle: "Modern · light gray · subtle aggregate",
                    icon: "square.fill",
                    imageAssetName: "CategoryThumbs/25_game_room",
                    prompt: "Polished concrete flooring with a clean modern finish, light gray with subtle aggregate, sealed to a satin sheen."
                ),
                PromptCard(
                    id: "floor.lvp",
                    title: "Luxury Vinyl Plank",
                    subtitle: "Realistic oak grain · scratch-resistant",
                    icon: "rectangle.grid.3x2.fill",
                    imageAssetName: "CategoryThumbs/09_living_room",
                    prompt: "Luxury vinyl plank flooring with realistic oak grain, scratch-resistant wear layer, and beveled edges for a true wood look."
                ),
                PromptCard(
                    id: "floor.tile",
                    title: "Porcelain Tile",
                    subtitle: "Stone-look · large format · light gray",
                    icon: "square.grid.2x2.fill",
                    imageAssetName: "CategoryThumbs/16_entryway_foyer",
                    prompt: "Large-format porcelain tile in a stone-look finish, light gray with subtle veining, set with minimal grout lines."
                ),
            ]
        case .roofing:
            // The catalog has no roof close-up. We use exterior shots
            // where the roofline is a major compositional element
            // (facade, porch with visible eaves) and the attic-conversion
            // shot which shows roof structure from inside.
            return [
                PromptCard(
                    id: "roof.architectural",
                    title: "Architectural Shingle",
                    subtitle: "Dimensional · charcoal · 30-year",
                    icon: "house.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "New architectural asphalt shingle roof in dimensional charcoal, with matching ridge caps and clean drip edge detailing."
                ),
                PromptCard(
                    id: "roof.metal",
                    title: "Standing Seam Metal",
                    subtitle: "Galvalume · clean lines · modern",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "CategoryThumbs/34_front_porch",
                    prompt: "Standing-seam metal roof in galvalume finish with crisp ridge lines, integrated snow guards, and matching trim."
                ),
                PromptCard(
                    id: "roof.tile",
                    title: "Clay Tile",
                    subtitle: "Spanish · terra cotta · classic",
                    icon: "circle.grid.3x3.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Spanish-style clay tile roof in natural terra cotta, with rounded barrel tiles and decorative ridge caps."
                ),
                PromptCard(
                    id: "roof.slate",
                    title: "Synthetic Slate",
                    subtitle: "Composite · gray · long-lasting",
                    icon: "square.stack.fill",
                    imageAssetName: "CategoryThumbs/28_attic_conversion",
                    prompt: "Synthetic slate roof in graduated gray tones, with copper flashing details and a clean, refined appearance."
                ),
            ]
        case .painting:
            // Paint is on every wall — we pick rooms whose walls dominate
            // the frame (bedrooms, living rooms) for the interior cards.
            // The exterior-refresh card uses the facade shot since
            // exterior paint is the visible work product.
            return [
                PromptCard(
                    id: "paint.warm-neutral",
                    title: "Warm Neutral",
                    subtitle: "Greige · cream trim · cozy",
                    icon: "paintbrush.fill",
                    imageAssetName: "CategoryThumbs/04_guest_bedroom",
                    prompt: "Walls in a warm greige neutral with crisp cream trim and ceiling, creating a cozy and timeless palette."
                ),
                PromptCard(
                    id: "paint.modern",
                    title: "Modern Cool",
                    subtitle: "Soft white · charcoal trim · airy",
                    icon: "circle.lefthalf.filled",
                    imageAssetName: "CategoryThumbs/09_living_room",
                    prompt: "Walls in soft modern white with charcoal accent trim, providing a clean and airy contemporary look."
                ),
                PromptCard(
                    id: "paint.bold",
                    title: "Bold Accent",
                    subtitle: "Deep navy feature · white trim",
                    icon: "sparkle",
                    imageAssetName: "CategoryThumbs/03_master_bedroom",
                    prompt: "Deep navy blue accent wall with the remaining walls in soft white, complemented by bright white trim."
                ),
                PromptCard(
                    id: "paint.exterior",
                    title: "Exterior Refresh",
                    subtitle: "Body · trim · accent color combo",
                    icon: "house.lodge.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Fresh exterior paint with a thoughtful three-color combination — body, trim, and front door accent — that elevates curb appeal."
                ),
            ]
        case .siding:
            // Siding is exterior facade work. We rotate between the
            // facade and front-porch shots since both feature siding
            // prominently. No fence/in-law-suite reaches.
            return [
                PromptCard(
                    id: "siding.fiber",
                    title: "Fiber Cement",
                    subtitle: "Lap · soft white · architectural trim",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Fiber cement lap siding in soft white with architectural trim and corner boards, replacing aging existing siding."
                ),
                PromptCard(
                    id: "siding.vinyl",
                    title: "Vinyl Premium",
                    subtitle: "Insulated · low-maintenance",
                    icon: "shield.lefthalf.filled",
                    imageAssetName: "CategoryThumbs/34_front_porch",
                    prompt: "Premium insulated vinyl siding in a warm tan, with matching soffit, fascia, and seamless gutters."
                ),
                PromptCard(
                    id: "siding.cedar",
                    title: "Cedar Shake",
                    subtitle: "Stained · natural · craftsman",
                    icon: "leaf.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Cedar shake siding with a transparent stain showing natural grain, accented with stone veneer at the foundation."
                ),
                PromptCard(
                    id: "siding.modern",
                    title: "Modern Mixed",
                    subtitle: "Vertical board & batten · stone",
                    icon: "square.split.2x1.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Modern mixed siding combining vertical board-and-batten with horizontal lap accents and a stone veneer base."
                ),
            ]
        case .roomRemodel:
            // Room remodel is style-agnostic — any finished room reads
            // honestly. Pair each style card with a room whose mood
            // genuinely matches: home office for "modern," library for
            // "transitional" classic millwork, sunroom for the airy
            // Scandinavian feel, game room for industrial.
            return [
                PromptCard(
                    id: "room.modern",
                    title: "Modern",
                    subtitle: "Clean lines · neutral palette · light",
                    icon: "square.dashed",
                    imageAssetName: "CategoryThumbs/17_home_office",
                    prompt: "Modern room with clean architectural lines, a soft neutral palette, hardwood floors, and abundant natural light."
                ),
                PromptCard(
                    id: "room.transitional",
                    title: "Transitional",
                    subtitle: "Mix of classic & contemporary",
                    icon: "arrow.triangle.merge",
                    imageAssetName: "CategoryThumbs/18_library",
                    prompt: "Transitional space blending classic millwork with contemporary furnishings, layered textures, and warm wood tones."
                ),
                PromptCard(
                    id: "room.scandinavian",
                    title: "Scandinavian",
                    subtitle: "Light wood · white · cozy textiles",
                    icon: "snowflake",
                    imageAssetName: "CategoryThumbs/27_sunroom",
                    prompt: "Scandinavian room with light oak floors, white walls, simple furniture, and cozy textiles for warmth."
                ),
                PromptCard(
                    id: "room.industrial",
                    title: "Industrial",
                    subtitle: "Exposed brick · metal · vintage",
                    icon: "gearshape.2.fill",
                    imageAssetName: "CategoryThumbs/25_game_room",
                    prompt: "Industrial-leaning room with exposed brick, blackened steel accents, vintage furniture, and Edison-bulb fixtures."
                ),
            ]
        case .exterior:
            // Exterior cards stick to genuine exterior shots — facade,
            // front porch, screened porch, and driveway. No bedroom or
            // garden substitutes.
            return [
                PromptCard(
                    id: "exterior.modern",
                    title: "Modern Refresh",
                    subtitle: "Clean lines · bold front door",
                    icon: "house.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Modern exterior refresh with crisp white siding, a bold black front door, minimalist landscape lighting, and architectural house numbers."
                ),
                PromptCard(
                    id: "exterior.craftsman",
                    title: "Craftsman",
                    subtitle: "Cedar accents · stone base · pillars",
                    icon: "tree.fill",
                    imageAssetName: "CategoryThumbs/34_front_porch",
                    prompt: "Craftsman-style exterior with stained cedar accents, a stone veneer base, tapered porch pillars, and warm exterior lighting."
                ),
                PromptCard(
                    id: "exterior.modern-farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "Board & batten · black accents",
                    icon: "house.lodge.fill",
                    imageAssetName: "CategoryThumbs/33_exterior_facade",
                    prompt: "Modern farmhouse exterior with white board-and-batten siding, black window frames, metal roof accents, and a covered front porch."
                ),
                PromptCard(
                    id: "exterior.coastal",
                    title: "Coastal",
                    subtitle: "Shingle · soft blue · weathered",
                    icon: "wind",
                    imageAssetName: "CategoryThumbs/40_screened_porch",
                    prompt: "Coastal exterior with cedar shingle siding weathered to a silver patina, soft blue trim, and a welcoming front porch."
                ),
            ]
        case .landscaping:
            return [
                PromptCard(
                    id: "land.modern",
                    title: "Modern Minimalist",
                    subtitle: "Clean planting beds · gravel · steel",
                    icon: "rectangle.3.offgrid.fill",
                    imageAssetName: "CategoryThumbs/44_hardscape",
                    prompt: "Modern minimalist landscape with clean rectangular planting beds, ornamental grasses, decorative gravel, and corten steel edging."
                ),
                PromptCard(
                    id: "land.cottage",
                    title: "Cottage Garden",
                    subtitle: "Layered perennials · flagstone path",
                    icon: "leaf.fill",
                    imageAssetName: "CategoryThumbs/46_backyard_garden",
                    prompt: "Cottage-style garden with layered perennials, a winding flagstone path, climbing roses, and a small seating nook."
                ),
                PromptCard(
                    id: "land.xeriscape",
                    title: "Drought-Tolerant",
                    subtitle: "Native plants · mulch · efficient",
                    icon: "drop.degreesign.slash",
                    imageAssetName: "CategoryThumbs/47_vegetable_garden",
                    prompt: "Drought-tolerant xeriscape with native grasses, succulents, decorative boulders, and efficient drip irrigation."
                ),
                PromptCard(
                    id: "land.entertaining",
                    title: "Outdoor Living",
                    subtitle: "Patio · firepit · pergola",
                    icon: "flame.fill",
                    imageAssetName: "CategoryThumbs/50_fire_pit",
                    prompt: "Outdoor living landscape featuring a paver patio, gas firepit with seating, cedar pergola, and ambient string lighting."
                ),
            ]
        case .lawnCare:
            // Lawn care = grass-only work. We pick shots where the lawn
            // is the visible subject: front yard, backyard with turf, the
            // putting green for high-maintenance fertilization, and the
            // backyard garden where seasonal cleanup happens at bed
            // edges.
            return [
                PromptCard(
                    id: "lawn.weekly",
                    title: "Weekly Maintenance",
                    subtitle: "Mow · edge · blow · trim",
                    icon: "leaf.fill",
                    imageAssetName: "CategoryThumbs/45_front_yard",
                    prompt: "Recurring weekly lawn maintenance: precision mowing, hard-edge work, debris blowing, and periodic shrub trimming."
                ),
                PromptCard(
                    id: "lawn.fert",
                    title: "Fertilization Program",
                    subtitle: "Multi-step · seasonal · weed control",
                    icon: "drop.fill",
                    imageAssetName: "CategoryThumbs/54_putting_green",
                    prompt: "Multi-step seasonal fertilization program with pre-emergent weed control, targeted nutrients, and broadleaf treatments."
                ),
                PromptCard(
                    id: "lawn.aeration",
                    title: "Aeration & Overseed",
                    subtitle: "Core aerate · top-quality seed",
                    icon: "circle.grid.cross.fill",
                    imageAssetName: "CategoryThumbs/45_front_yard",
                    prompt: "Annual core aeration with overseed using top-quality cool-season turf blend, topdressed for healthy establishment."
                ),
                PromptCard(
                    id: "lawn.cleanup",
                    title: "Spring/Fall Cleanup",
                    subtitle: "Bed clearing · leaves · trim back",
                    icon: "wind",
                    imageAssetName: "CategoryThumbs/46_backyard_garden",
                    prompt: "Comprehensive spring or fall cleanup: bed clearing, leaf removal, hard prune of shrubs, and fresh edging."
                ),
            ]
        case .outdoorLiving:
            return [
                PromptCard(
                    id: "outdoor.patio",
                    title: "Paver Patio",
                    subtitle: "Flagstone · pergola · seating",
                    icon: "square.grid.2x2.fill",
                    imageAssetName: "CategoryThumbs/36_outdoor_patio",
                    prompt: "Refined paver patio with flagstone borders, a covered pergola overhead, built-in bench seating, and ambient string lighting."
                ),
                PromptCard(
                    id: "outdoor.kitchen",
                    title: "Outdoor Kitchen",
                    subtitle: "Built-in grill · stone counter · bar",
                    icon: "flame.fill",
                    imageAssetName: "CategoryThumbs/37_outdoor_kitchen",
                    prompt: "Outdoor kitchen with a built-in stainless grill, stone-clad counter, side burner, integrated refrigerator, and a covered bar with stools."
                ),
                PromptCard(
                    id: "outdoor.pergola",
                    title: "Pergola & Shade",
                    subtitle: "Cedar beams · slatted top · vines",
                    icon: "rectangle.split.3x1.fill",
                    imageAssetName: "CategoryThumbs/38_pergola",
                    prompt: "Cedar pergola with slatted top, climbing vines, retractable shade cloth, and integrated downlighting for evening use."
                ),
                PromptCard(
                    id: "outdoor.firepit",
                    title: "Firepit Lounge",
                    subtitle: "Gas firepit · stone surround · cozy",
                    icon: "flame.circle.fill",
                    imageAssetName: "CategoryThumbs/50_fire_pit",
                    prompt: "Gas firepit lounge with a circular stone surround, weather-resistant lounge seating, and a paver landing with low landscape lighting."
                ),
            ]
        case .garage:
            return [
                PromptCard(
                    id: "garage.workshop",
                    title: "Workshop Fit-Out",
                    subtitle: "Wall-to-wall benches · pegboard · LED",
                    icon: "wrench.and.screwdriver.fill",
                    imageAssetName: "CategoryThumbs/29_garage_workshop",
                    prompt: "Garage workshop fit-out with wall-to-wall hardwood workbenches, pegboard tool storage, slatwall accessories, epoxy floor coating, and bright LED panel lighting."
                ),
                PromptCard(
                    id: "garage.ev",
                    title: "EV-Ready Bay",
                    subtitle: "Level 2 charger · sealed floor · clean",
                    icon: "bolt.car.fill",
                    imageAssetName: "CategoryThumbs/35_driveway",
                    prompt: "Modern garage upgrade with a wall-mounted Level 2 EV charger, sealed concrete floor, recessed cable management, motion-activated LEDs, and an insulated overhead door."
                ),
                PromptCard(
                    id: "garage.conversion",
                    title: "Livable Conversion",
                    subtitle: "Office or studio · insulated · finished",
                    icon: "rectangle.3.group.fill",
                    imageAssetName: "CategoryThumbs/30_garage_conversion",
                    prompt: "Garage converted to a finished livable studio with insulated walls and ceiling, drywall and trim, vinyl plank flooring, mini-split HVAC, and large windows replacing the overhead door."
                ),
                PromptCard(
                    id: "garage.storage",
                    title: "Storage & Organization",
                    subtitle: "Overhead racks · cabinets · ceiling lift",
                    icon: "shippingbox.fill",
                    imageAssetName: "CategoryThumbs/29_garage_workshop",
                    prompt: "Garage storage and organization with overhead ceiling racks, full-height steel cabinetry, slatwall hooks, bicycle and kayak hoists, and a clean labeled-bin system."
                ),
            ]
        case .custom:
            return genericFallback
        }
    }

    /// Generic fallback when a category isn't yet specifically curated.
    /// Currently only used by `.custom`, but kept centralized so any new
    /// `ProjectType` cases compile without an exhaustive-switch break.
    private static let genericFallback: [PromptCard] = [
        PromptCard(
            id: "generic.modern",
            title: "Modern",
            subtitle: "Clean lines · contemporary materials",
            icon: "square.dashed",
            imageAssetName: "CategoryThumbs/25_game_room",
            prompt: "Modern design with clean lines, contemporary materials, and a thoughtful neutral palette."
        ),
        PromptCard(
            id: "generic.traditional",
            title: "Traditional",
            subtitle: "Classic detailing · warm tones",
            icon: "building.columns.fill",
            imageAssetName: "CategoryThumbs/18_library",
            prompt: "Traditional design with classic detailing, warm wood tones, and timeless finishes."
        ),
        PromptCard(
            id: "generic.minimal",
            title: "Minimalist",
            subtitle: "Spare · refined · light",
            icon: "circle.dotted",
            imageAssetName: "CategoryThumbs/23_yoga_room",
            prompt: "Minimalist design that's spare and refined, with light tones and uncluttered surfaces."
        ),
        PromptCard(
            id: "generic.bold",
            title: "Bold Statement",
            subtitle: "High contrast · dramatic accents",
            icon: "sparkle",
            imageAssetName: "CategoryThumbs/21_wine_cellar",
            prompt: "Bold statement design with high-contrast colors, dramatic accents, and confident material choices."
        ),
    ]
}
