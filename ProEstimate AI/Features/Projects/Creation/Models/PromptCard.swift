import Foundation

/// A premade prompt suggestion shown in the creation flow as a tappable
/// card. Tapping populates the AI generation prompt with `prompt`; the
/// user can layer custom instructions on top in the input field below.
struct PromptCard: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let prompt: String
}

extension PromptCard {
    /// Per-category prompt suggestions surfaced in the creation flow.
    /// Always returns four cards so the carousel layout is predictable.
    static func suggestions(for type: Project.ProjectType) -> [PromptCard] {
        switch type {
        case .kitchen:
            return [
                PromptCard(
                    id: "kitchen.farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "White shaker · butcher block · matte black",
                    icon: "sun.max.fill",
                    prompt: "Modern farmhouse kitchen with white shaker cabinets, butcher block countertops, apron-front sink, matte black hardware, and warm pendant lighting."
                ),
                PromptCard(
                    id: "kitchen.contemporary",
                    title: "Contemporary",
                    subtitle: "Handle-less · waterfall quartz · integrated",
                    icon: "square.stack.3d.up.fill",
                    prompt: "Contemporary minimalist kitchen with handle-less flat-panel cabinets, a waterfall-edge quartz island, integrated appliances, and recessed LED lighting."
                ),
                PromptCard(
                    id: "kitchen.traditional",
                    title: "Traditional",
                    subtitle: "Raised panel · granite · crown molding",
                    icon: "leaf.fill",
                    prompt: "Traditional kitchen with raised-panel cherry cabinets, granite countertops, decorative crown molding, ceramic tile backsplash, and a farmhouse-style chandelier."
                ),
                PromptCard(
                    id: "kitchen.industrial",
                    title: "Industrial",
                    subtitle: "Concrete · brick · open shelving",
                    icon: "wrench.and.screwdriver.fill",
                    prompt: "Industrial kitchen with concrete countertops, exposed brick accent wall, open metal shelving, stainless steel appliances, and Edison-bulb pendant lighting."
                ),
            ]
        case .bathroom:
            return [
                PromptCard(
                    id: "bath.spa",
                    title: "Spa Retreat",
                    subtitle: "Walk-in shower · freestanding tub · marble",
                    icon: "drop.fill",
                    prompt: "Spa-like bathroom with a frameless walk-in shower, freestanding soaking tub, heated marble floors, and warm ambient lighting."
                ),
                PromptCard(
                    id: "bath.minimal",
                    title: "Modern Minimalist",
                    subtitle: "Floating vanity · vessel sink · porcelain",
                    icon: "circle.dotted",
                    prompt: "Modern minimalist bathroom with a floating wood vanity, vessel sink, large-format porcelain tile, brushed nickel fixtures, and backlit mirror."
                ),
                PromptCard(
                    id: "bath.classic",
                    title: "Classic",
                    subtitle: "Subway tile · claw-foot · beadboard",
                    icon: "building.columns.fill",
                    prompt: "Classic bathroom with white subway tile, a claw-foot tub, beadboard wainscoting, polished chrome fixtures, and a hexagonal mosaic floor."
                ),
                PromptCard(
                    id: "bath.coastal",
                    title: "Coastal",
                    subtitle: "Shiplap · weathered wood · seafoam",
                    icon: "wind",
                    prompt: "Coastal bathroom with shiplap walls, a weathered wood vanity, white quartz countertop, seafoam-green accents, and a pebble shower floor."
                ),
            ]
        case .flooring:
            return [
                PromptCard(
                    id: "floor.hardwood",
                    title: "Wide-Plank Hardwood",
                    subtitle: "Engineered oak · matte · wire-brushed",
                    icon: "rectangle.stack.fill",
                    prompt: "Wide-plank engineered hardwood flooring in warm matte oak with a subtle wire-brushed texture, installed throughout the space."
                ),
                PromptCard(
                    id: "floor.concrete",
                    title: "Polished Concrete",
                    subtitle: "Modern · light gray · subtle aggregate",
                    icon: "square.fill",
                    prompt: "Polished concrete flooring with a clean modern finish, light gray with subtle aggregate, sealed to a satin sheen."
                ),
                PromptCard(
                    id: "floor.lvp",
                    title: "Luxury Vinyl Plank",
                    subtitle: "Realistic oak grain · scratch-resistant",
                    icon: "rectangle.grid.3x2.fill",
                    prompt: "Luxury vinyl plank flooring with realistic oak grain, scratch-resistant wear layer, and beveled edges for a true wood look."
                ),
                PromptCard(
                    id: "floor.tile",
                    title: "Porcelain Tile",
                    subtitle: "Stone-look · large format · light gray",
                    icon: "square.grid.2x2.fill",
                    prompt: "Large-format porcelain tile in a stone-look finish, light gray with subtle veining, set with minimal grout lines."
                ),
            ]
        case .roofing:
            return [
                PromptCard(
                    id: "roof.architectural",
                    title: "Architectural Shingle",
                    subtitle: "Dimensional · charcoal · 30-year",
                    icon: "house.fill",
                    prompt: "New architectural asphalt shingle roof in dimensional charcoal, with matching ridge caps and clean drip edge detailing."
                ),
                PromptCard(
                    id: "roof.metal",
                    title: "Standing Seam Metal",
                    subtitle: "Galvalume · clean lines · modern",
                    icon: "rectangle.split.3x1.fill",
                    prompt: "Standing-seam metal roof in galvalume finish with crisp ridge lines, integrated snow guards, and matching trim."
                ),
                PromptCard(
                    id: "roof.tile",
                    title: "Clay Tile",
                    subtitle: "Spanish · terra cotta · classic",
                    icon: "circle.grid.3x3.fill",
                    prompt: "Spanish-style clay tile roof in natural terra cotta, with rounded barrel tiles and decorative ridge caps."
                ),
                PromptCard(
                    id: "roof.slate",
                    title: "Synthetic Slate",
                    subtitle: "Composite · gray · long-lasting",
                    icon: "square.stack.fill",
                    prompt: "Synthetic slate roof in graduated gray tones, with copper flashing details and a clean, refined appearance."
                ),
            ]
        case .painting:
            return [
                PromptCard(
                    id: "paint.warm-neutral",
                    title: "Warm Neutral",
                    subtitle: "Greige · cream trim · cozy",
                    icon: "paintbrush.fill",
                    prompt: "Walls in a warm greige neutral with crisp cream trim and ceiling, creating a cozy and timeless palette."
                ),
                PromptCard(
                    id: "paint.modern",
                    title: "Modern Cool",
                    subtitle: "Soft white · charcoal trim · airy",
                    icon: "circle.lefthalf.filled",
                    prompt: "Walls in soft modern white with charcoal accent trim, providing a clean and airy contemporary look."
                ),
                PromptCard(
                    id: "paint.bold",
                    title: "Bold Accent",
                    subtitle: "Deep navy feature · white trim",
                    icon: "sparkle",
                    prompt: "Deep navy blue accent wall with the remaining walls in soft white, complemented by bright white trim."
                ),
                PromptCard(
                    id: "paint.exterior",
                    title: "Exterior Refresh",
                    subtitle: "Body · trim · accent color combo",
                    icon: "house.lodge.fill",
                    prompt: "Fresh exterior paint with a thoughtful three-color combination — body, trim, and front door accent — that elevates curb appeal."
                ),
            ]
        case .siding:
            return [
                PromptCard(
                    id: "siding.fiber",
                    title: "Fiber Cement",
                    subtitle: "Lap · soft white · architectural trim",
                    icon: "rectangle.split.3x1.fill",
                    prompt: "Fiber cement lap siding in soft white with architectural trim and corner boards, replacing aging existing siding."
                ),
                PromptCard(
                    id: "siding.vinyl",
                    title: "Vinyl Premium",
                    subtitle: "Insulated · low-maintenance",
                    icon: "shield.lefthalf.filled",
                    prompt: "Premium insulated vinyl siding in a warm tan, with matching soffit, fascia, and seamless gutters."
                ),
                PromptCard(
                    id: "siding.cedar",
                    title: "Cedar Shake",
                    subtitle: "Stained · natural · craftsman",
                    icon: "leaf.fill",
                    prompt: "Cedar shake siding with a transparent stain showing natural grain, accented with stone veneer at the foundation."
                ),
                PromptCard(
                    id: "siding.modern",
                    title: "Modern Mixed",
                    subtitle: "Vertical board & batten · stone",
                    icon: "square.split.2x1.fill",
                    prompt: "Modern mixed siding combining vertical board-and-batten with horizontal lap accents and a stone veneer base."
                ),
            ]
        case .roomRemodel:
            return [
                PromptCard(
                    id: "room.modern",
                    title: "Modern",
                    subtitle: "Clean lines · neutral palette · light",
                    icon: "square.dashed",
                    prompt: "Modern room with clean architectural lines, a soft neutral palette, hardwood floors, and abundant natural light."
                ),
                PromptCard(
                    id: "room.transitional",
                    title: "Transitional",
                    subtitle: "Mix of classic & contemporary",
                    icon: "arrow.triangle.merge",
                    prompt: "Transitional space blending classic millwork with contemporary furnishings, layered textures, and warm wood tones."
                ),
                PromptCard(
                    id: "room.scandinavian",
                    title: "Scandinavian",
                    subtitle: "Light wood · white · cozy textiles",
                    icon: "snowflake",
                    prompt: "Scandinavian room with light oak floors, white walls, simple furniture, and cozy textiles for warmth."
                ),
                PromptCard(
                    id: "room.industrial",
                    title: "Industrial",
                    subtitle: "Exposed brick · metal · vintage",
                    icon: "gearshape.2.fill",
                    prompt: "Industrial-leaning room with exposed brick, blackened steel accents, vintage furniture, and Edison-bulb fixtures."
                ),
            ]
        case .exterior:
            return [
                PromptCard(
                    id: "exterior.modern",
                    title: "Modern Refresh",
                    subtitle: "Clean lines · bold front door",
                    icon: "house.fill",
                    prompt: "Modern exterior refresh with crisp white siding, a bold black front door, minimalist landscape lighting, and architectural house numbers."
                ),
                PromptCard(
                    id: "exterior.craftsman",
                    title: "Craftsman",
                    subtitle: "Cedar accents · stone base · pillars",
                    icon: "tree.fill",
                    prompt: "Craftsman-style exterior with stained cedar accents, a stone veneer base, tapered porch pillars, and warm exterior lighting."
                ),
                PromptCard(
                    id: "exterior.modern-farmhouse",
                    title: "Modern Farmhouse",
                    subtitle: "Board & batten · black accents",
                    icon: "barn.fill",
                    prompt: "Modern farmhouse exterior with white board-and-batten siding, black window frames, metal roof accents, and a covered front porch."
                ),
                PromptCard(
                    id: "exterior.coastal",
                    title: "Coastal",
                    subtitle: "Shingle · soft blue · weathered",
                    icon: "wind",
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
                    prompt: "Modern minimalist landscape with clean rectangular planting beds, ornamental grasses, decorative gravel, and corten steel edging."
                ),
                PromptCard(
                    id: "land.cottage",
                    title: "Cottage Garden",
                    subtitle: "Layered perennials · flagstone path",
                    icon: "leaf.fill",
                    prompt: "Cottage-style garden with layered perennials, a winding flagstone path, climbing roses, and a small seating nook."
                ),
                PromptCard(
                    id: "land.xeriscape",
                    title: "Drought-Tolerant",
                    subtitle: "Native plants · mulch · efficient",
                    icon: "drop.degreesign.slash",
                    prompt: "Drought-tolerant xeriscape with native grasses, succulents, decorative boulders, and efficient drip irrigation."
                ),
                PromptCard(
                    id: "land.entertaining",
                    title: "Outdoor Living",
                    subtitle: "Patio · firepit · pergola",
                    icon: "flame.fill",
                    prompt: "Outdoor living landscape featuring a paver patio, gas firepit with seating, cedar pergola, and ambient string lighting."
                ),
            ]
        case .lawnCare:
            return [
                PromptCard(
                    id: "lawn.weekly",
                    title: "Weekly Maintenance",
                    subtitle: "Mow · edge · blow · trim",
                    icon: "leaf.fill",
                    prompt: "Recurring weekly lawn maintenance: precision mowing, hard-edge work, debris blowing, and periodic shrub trimming."
                ),
                PromptCard(
                    id: "lawn.fert",
                    title: "Fertilization Program",
                    subtitle: "Multi-step · seasonal · weed control",
                    icon: "drop.fill",
                    prompt: "Multi-step seasonal fertilization program with pre-emergent weed control, targeted nutrients, and broadleaf treatments."
                ),
                PromptCard(
                    id: "lawn.aeration",
                    title: "Aeration & Overseed",
                    subtitle: "Core aerate · top-quality seed",
                    icon: "circle.grid.cross.fill",
                    prompt: "Annual core aeration with overseed using top-quality cool-season turf blend, topdressed for healthy establishment."
                ),
                PromptCard(
                    id: "lawn.cleanup",
                    title: "Spring/Fall Cleanup",
                    subtitle: "Bed clearing · leaves · trim back",
                    icon: "wind",
                    prompt: "Comprehensive spring or fall cleanup: bed clearing, leaf removal, hard prune of shrubs, and fresh edging."
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
            prompt: "Modern design with clean lines, contemporary materials, and a thoughtful neutral palette."
        ),
        PromptCard(
            id: "generic.traditional",
            title: "Traditional",
            subtitle: "Classic detailing · warm tones",
            icon: "building.columns.fill",
            prompt: "Traditional design with classic detailing, warm wood tones, and timeless finishes."
        ),
        PromptCard(
            id: "generic.minimal",
            title: "Minimalist",
            subtitle: "Spare · refined · light",
            icon: "circle.dotted",
            prompt: "Minimalist design that's spare and refined, with light tones and uncluttered surfaces."
        ),
        PromptCard(
            id: "generic.bold",
            title: "Bold Statement",
            subtitle: "High contrast · dramatic accents",
            icon: "sparkle",
            prompt: "Bold statement design with high-contrast colors, dramatic accents, and confident material choices."
        ),
    ]
}
