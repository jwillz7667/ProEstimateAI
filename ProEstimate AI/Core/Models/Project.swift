import Foundation

/// Represents a remodel or construction project.
/// Projects are the central entity in the app — they link photos, AI generations,
/// estimates, proposals, and invoices into one coherent workflow.
struct Project: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let companyId: String
    let clientId: String?
    let title: String
    let description: String?
    let projectType: ProjectType
    let status: Status
    let budgetMin: Decimal?
    let budgetMax: Decimal?
    /// Optional. `nil` means "Auto" — the backend chooses tier-neutral defaults
    /// driven by the project type. When set, every downstream artifact (image
    /// prompt, materials, estimate, post-AI clamps) is anchored to this tier's
    /// price/quality bounds via `backend/src/lib/prompts/tier-bounds.ts`.
    let qualityTier: QualityTier?
    let squareFootage: Decimal?
    let dimensions: String?
    let language: String?
    /// Measured lawn area in sq ft. Populated by the lawn-measurement
    /// MapKit polygon flow; consumed by the LAWN_CARE prompt module to
    /// quote per-acre material and labor against the actual property.
    let lawnAreaSqFt: Decimal?
    /// Measured roof area in sq ft. Populated by the roof scouting flow
    /// (Google Solar API segments). Consumed by the ROOFING prompt
    /// module which converts to "squares" (100 sq ft) for material
    /// quantities.
    let roofAreaSqFt: Decimal?
    let propertyLatitude: Decimal?
    let propertyLongitude: Decimal?
    /// Recurring service contract flag. When true, the estimate UI shows
    /// per-visit / monthly / annual rollups instead of a single total.
    let isRecurring: Bool
    /// Cadence string from the backend ("weekly", "biweekly", "monthly",
    /// "quarterly", "seasonal"). Decoded via `RecurrenceFrequency` for
    /// type-safe comparisons in the UI.
    let recurrenceFrequency: RecurrenceFrequency?
    /// Optional override of the canonical visits-per-month for the
    /// frequency. Real properties skip mowing during dormancy or get
    /// extra spring visits — store the truth.
    let visitsPerMonth: Decimal?
    /// Length of the contract in months (e.g. 8 = April–November cool-
    /// season growing window).
    let contractMonths: Int?
    let recurrenceStartDate: Date?
    let createdAt: Date
    let updatedAt: Date
    /// Resolves to the project's most recent COMPLETED generation preview, or
    /// the first ORIGINAL asset image if no generation exists. Server-provided
    /// (see backend `projects.dto.ts → thumbnail_url`); nil for new projects.
    let thumbnailURL: URL?

    // MARK: - Nested Enums

    /// The category of remodel or construction work.
    ///
    /// Renamed `exterior` displayName from "Exterior / Outdoor Living"
    /// to just "Exterior" once `outdoorLiving` was added — outdoor decks,
    /// patios, pergolas, pools, and firepits live there now, leaving
    /// `exterior` to mean curb appeal / facade work specifically.
    enum ProjectType: String, Codable, CaseIterable, Sendable {
        case kitchen
        case bathroom
        case flooring
        case roofing
        case painting
        case siding
        case roomRemodel = "room_remodel"
        case exterior
        case landscaping
        case lawnCare = "lawn_care"
        case outdoorLiving = "outdoor_living"
        case garage
        case custom

        /// Display name for project type pickers and detail headers.
        var displayName: String {
            switch self {
            case .kitchen: return "Kitchen"
            case .bathroom: return "Bathroom"
            case .flooring: return "Flooring"
            case .roofing: return "Roofing"
            case .painting: return "Painting"
            case .siding: return "Siding"
            case .roomRemodel: return "Room Remodel"
            case .exterior: return "Exterior"
            case .landscaping: return "Landscaping"
            case .lawnCare: return "Lawn Care"
            case .outdoorLiving: return "Outdoor Living"
            case .garage: return "Garage"
            case .custom: return "Custom"
            }
        }

        /// SF Symbol used in legacy small-icon contexts (project list rows,
        /// dashboard tiles, detail header). The new image-driven category
        /// picker uses `thumbnailAssetName` instead.
        var iconName: String {
            switch self {
            case .kitchen: return "fork.knife"
            case .bathroom: return "shower.fill"
            case .flooring: return "rectangle.grid.2x2"
            case .roofing: return "house.fill"
            case .painting: return "paintbrush.fill"
            case .siding: return "square.split.bottomrightquarter"
            case .roomRemodel: return "rectangle.3.group"
            case .exterior: return "house.lodge"
            case .landscaping: return "leaf.fill"
            case .lawnCare: return "scissors"
            case .outdoorLiving: return "sofa.fill"
            case .garage: return "car.fill"
            case .custom: return "wrench.and.screwdriver"
            }
        }

        /// Asset-catalog name of the dedicated category hero rendered in
        /// the project creation category picker. One bespoke HEIC per
        /// category lives under `Assets.xcassets/CategoryTiles/` — unlike
        /// the legacy `CategoryThumbs/` library (which is a shared pool of
        /// generic room photos), each tile here is purpose-shot for its
        /// category and never reused across categories.
        var thumbnailAssetName: String {
            switch self {
            case .kitchen: return "CategoryTiles/01_kitchen"
            case .bathroom: return "CategoryTiles/02_bathroom"
            case .flooring: return "CategoryTiles/03_flooring"
            case .roofing: return "CategoryTiles/04_roofing"
            case .painting: return "CategoryTiles/05_painting"
            case .siding: return "CategoryTiles/06_siding"
            case .roomRemodel: return "CategoryTiles/07_room_remodel"
            case .exterior: return "CategoryTiles/08_exterior"
            case .landscaping: return "CategoryTiles/09_landscaping"
            case .lawnCare: return "CategoryTiles/10_lawn_care"
            case .outdoorLiving: return "CategoryTiles/11_outdoor_living"
            case .garage: return "CategoryTiles/12_garage"
            case .custom: return "CategoryTiles/13_custom"
            }
        }

        /// Whether projects of this type are typically recurring service
        /// contracts. Drives the recurrence UI in the project creation
        /// wizard and estimate editor.
        var isRecurringByDefault: Bool {
            self == .lawnCare
        }
    }

    /// Tracks the project through the full lifecycle from draft to completion.
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft
        case photosUploaded = "photos_uploaded"
        case generating
        case generationComplete = "generation_complete"
        case estimateCreated = "estimate_created"
        case proposalSent = "proposal_sent"
        case approved
        case declined
        case invoiced
        case completed
        case archived
    }

    /// Material and finish quality tier, affects AI generation and cost estimation.
    /// Optional on `Project` — `nil` means "Auto" (backend picks tier-neutral
    /// defaults). When set, the backend enforces tier price floors/ceilings on
    /// materials and labor via `tier-bounds.ts`.
    enum QualityTier: String, Codable, CaseIterable, Sendable {
        case standard
        case premium
        case luxury

        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .premium: return "Premium"
            case .luxury: return "Luxury"
            }
        }

        /// Short helper text shown under each option in the picker. Sets
        /// expectations on price band so contractors don't have to guess.
        var subtitle: String {
            switch self {
            case .standard: return "Builder-grade materials, contractor labor rates"
            case .premium: return "Mid-range finishes, skilled trade labor"
            case .luxury: return "High-end finishes, master tradesperson labor"
            }
        }
    }

    /// Cadence options for recurring service contracts. Stored as the
    /// raw string in the backend so adding a future cadence doesn't
    /// require an enum migration on either side.
    enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
        case weekly
        case biweekly
        case monthly
        case quarterly
        case seasonal

        var displayName: String {
            switch self {
            case .weekly: return "Weekly"
            case .biweekly: return "Every 2 Weeks"
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .seasonal: return "Seasonal"
            }
        }

        /// Default visits-per-month when the contractor hasn't overridden.
        /// Mirrors `defaultVisitsPerMonth` on the backend.
        var defaultVisitsPerMonth: Decimal {
            switch self {
            case .weekly: return 4
            case .biweekly: return 2
            case .monthly: return 1
            case .quarterly: return Decimal(1) / Decimal(3)
            case .seasonal: return 1
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case clientId = "client_id"
        case title
        case description
        case projectType = "project_type"
        case status
        case budgetMin = "budget_min"
        case budgetMax = "budget_max"
        case qualityTier = "quality_tier"
        case squareFootage = "square_footage"
        case dimensions
        case language
        case lawnAreaSqFt = "lawn_area_sq_ft"
        case roofAreaSqFt = "roof_area_sq_ft"
        case propertyLatitude = "property_latitude"
        case propertyLongitude = "property_longitude"
        case isRecurring = "is_recurring"
        case recurrenceFrequency = "recurrence_frequency"
        case visitsPerMonth = "visits_per_month"
        case contractMonths = "contract_months"
        case recurrenceStartDate = "recurrence_start_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case thumbnailURL = "thumbnail_url"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        companyId = try c.decode(String.self, forKey: .companyId)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        projectType = try c.decode(ProjectType.self, forKey: .projectType)
        status = try c.decode(Status.self, forKey: .status)
        budgetMin = try c.decodeIfPresent(Decimal.self, forKey: .budgetMin)
        budgetMax = try c.decodeIfPresent(Decimal.self, forKey: .budgetMax)
        qualityTier = try c.decodeIfPresent(QualityTier.self, forKey: .qualityTier)
        squareFootage = try c.decodeIfPresent(Decimal.self, forKey: .squareFootage)
        dimensions = try c.decodeIfPresent(String.self, forKey: .dimensions)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        lawnAreaSqFt = try c.decodeIfPresent(Decimal.self, forKey: .lawnAreaSqFt)
        roofAreaSqFt = try c.decodeIfPresent(Decimal.self, forKey: .roofAreaSqFt)
        propertyLatitude = try c.decodeIfPresent(Decimal.self, forKey: .propertyLatitude)
        propertyLongitude = try c.decodeIfPresent(Decimal.self, forKey: .propertyLongitude)
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        recurrenceFrequency = try c.decodeIfPresent(RecurrenceFrequency.self, forKey: .recurrenceFrequency)
        visitsPerMonth = try c.decodeIfPresent(Decimal.self, forKey: .visitsPerMonth)
        contractMonths = try c.decodeIfPresent(Int.self, forKey: .contractMonths)
        recurrenceStartDate = try c.decodeIfPresent(Date.self, forKey: .recurrenceStartDate)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    }

    init(
        id: String,
        companyId: String,
        clientId: String?,
        title: String,
        description: String?,
        projectType: ProjectType,
        status: Status,
        budgetMin: Decimal?,
        budgetMax: Decimal?,
        qualityTier: QualityTier? = nil,
        squareFootage: Decimal?,
        dimensions: String?,
        language: String?,
        lawnAreaSqFt: Decimal? = nil,
        roofAreaSqFt: Decimal? = nil,
        propertyLatitude: Decimal? = nil,
        propertyLongitude: Decimal? = nil,
        isRecurring: Bool = false,
        recurrenceFrequency: RecurrenceFrequency? = nil,
        visitsPerMonth: Decimal? = nil,
        contractMonths: Int? = nil,
        recurrenceStartDate: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.clientId = clientId
        self.title = title
        self.description = description
        self.projectType = projectType
        self.status = status
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.qualityTier = qualityTier
        self.squareFootage = squareFootage
        self.dimensions = dimensions
        self.language = language
        self.lawnAreaSqFt = lawnAreaSqFt
        self.roofAreaSqFt = roofAreaSqFt
        self.propertyLatitude = propertyLatitude
        self.propertyLongitude = propertyLongitude
        self.isRecurring = isRecurring
        self.recurrenceFrequency = recurrenceFrequency
        self.visitsPerMonth = visitsPerMonth
        self.contractMonths = contractMonths
        self.recurrenceStartDate = recurrenceStartDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - Convenience

extension Project {
    /// Budget range formatted for display, e.g. "$15,000 – $25,000".
    var budgetRangeDisplay: String? {
        guard let min = budgetMin else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let minStr = formatter.string(from: min as NSDecimalNumber) ?? "\(min)"
        if let max = budgetMax {
            let maxStr = formatter.string(from: max as NSDecimalNumber) ?? "\(max)"
            return "\(minStr) – \(maxStr)"
        }
        return minStr
    }

    /// Whether the project is in a terminal state.
    var isFinalized: Bool {
        switch status {
        case .completed, .archived:
            return true
        default:
            return false
        }
    }

    /// Whether the project has an active AI generation in progress.
    var isGenerating: Bool {
        status == .generating
    }

    /// Effective visits-per-month for a recurring contract: the explicit
    /// override if set, otherwise the cadence default. Returns nil when
    /// the project isn't recurring or has no frequency set.
    var effectiveVisitsPerMonth: Decimal? {
        guard isRecurring else { return nil }
        if let v = visitsPerMonth { return v }
        return recurrenceFrequency?.defaultVisitsPerMonth
    }

    /// Project a per-visit subtotal into a monthly amount. The estimate
    /// editor calls this with a per-visit total computed from line items.
    func monthlyTotal(perVisit: Decimal) -> Decimal? {
        guard let visits = effectiveVisitsPerMonth else { return nil }
        return perVisit * visits
    }

    /// Project a per-visit subtotal into the full contract total.
    func contractTotal(perVisit: Decimal) -> Decimal? {
        guard
            let monthly = monthlyTotal(perVisit: perVisit),
            let months = contractMonths
        else { return nil }
        return monthly * Decimal(months)
    }
}

// MARK: - Sample Data

extension Project {
    static let sample = Project(
        id: "p-001",
        companyId: "c-001",
        clientId: "cl-001",
        title: "Kitchen Remodel – Mitchell Residence",
        description: "Full kitchen remodel with new cabinets, countertops, and island.",
        projectType: .kitchen,
        status: .draft,
        budgetMin: 15000,
        budgetMax: 35000,
        qualityTier: .premium,
        squareFootage: 250,
        dimensions: "20x12.5",
        language: "en",
        createdAt: Date(),
        updatedAt: Date()
    )
}
