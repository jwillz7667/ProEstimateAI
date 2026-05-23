import Foundation

/// Visual style picker on the AI Remodel Studio screen.
/// Maps to the three "Style Vision" cards in the screenshot
/// (Modern / Farmhouse / Industrial) plus a few extras.
enum VisionStyle: String, CaseIterable, Identifiable {
    case modern
    case farmhouse
    case industrial
    case scandinavian
    case coastal
    case traditional

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .modern: "Modern"
        case .farmhouse: "Farmhouse"
        case .industrial: "Industrial"
        case .scandinavian: "Scandinavian"
        case .coastal: "Coastal"
        case .traditional: "Traditional"
        }
    }

    /// Short prose appended to the generation prompt so the AI biases toward
    /// the right material palette and silhouette.
    var promptHint: String {
        switch self {
        case .modern: "Modern style — clean lines, neutral palette, integrated lighting, matte finishes."
        case .farmhouse: "Farmhouse style — shaker cabinetry, warm wood tones, apron sink, soft white walls."
        case .industrial: "Industrial style — exposed brick or concrete, steel hardware, dark cabinetry, Edison bulbs."
        case .scandinavian: "Scandinavian style — pale woods, white surfaces, minimal hardware, abundant natural light."
        case .coastal: "Coastal style — soft blues and whites, weathered wood, brushed nickel fixtures."
        case .traditional: "Traditional style — classic millwork, raised-panel cabinets, warm metal accents."
        }
    }

    /// SF Symbol used in the swatch when no preview asset is provided.
    var iconName: String {
        switch self {
        case .modern: "square.grid.3x3"
        case .farmhouse: "leaf"
        case .industrial: "wrench.and.screwdriver"
        case .scandinavian: "snowflake"
        case .coastal: "drop"
        case .traditional: "book.closed"
        }
    }
}

/// Optional emphasis chips ("Material Focus") that ask the AI to keep
/// certain finishes prominent. Multi-select.
enum MaterialFocus: String, CaseIterable, Identifiable {
    case flooring
    case lighting
    case wallColor
    case cabinets
    case countertops
    case fixtures

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .flooring: "Flooring"
        case .lighting: "Lighting"
        case .wallColor: "Wall Color"
        case .cabinets: "Cabinets"
        case .countertops: "Countertops"
        case .fixtures: "Fixtures"
        }
    }

    var iconName: String {
        switch self {
        case .flooring: "square.split.bottomrightquarter"
        case .lighting: "lightbulb"
        case .wallColor: "paintpalette"
        case .cabinets: "rectangle.stack"
        case .countertops: "rectangle.bottomthird.inset.filled"
        case .fixtures: "drop.fill"
        }
    }

    /// Prose blurb glued onto the prompt so the AI emphasises this material.
    var promptHint: String {
        switch self {
        case .flooring: "Show specific flooring detail and wood grain."
        case .lighting: "Highlight the lighting design and fixtures."
        case .wallColor: "Make the wall color and finish prominent."
        case .cabinets: "Render the cabinet style and hardware in detail."
        case .countertops: "Emphasise countertop material, edge profile, and waterfall."
        case .fixtures: "Include detailed plumbing and hardware fixtures."
        }
    }
}
