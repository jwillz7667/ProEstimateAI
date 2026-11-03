import Foundation

struct EstimateTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let projectType: Project.ProjectType
    let itemCount: Int
    let totalAmount: Decimal
    let createdAt: Date
    let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case projectType = "project_type", itemCount = "item_count", totalAmount = "total_amount"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct SavedEstimateLibraryItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let category: EstimateLineItem.Category
    let name: String
    let description: String?
    let quantity: Decimal
    let unit: String
    let unitCost: Decimal
    let markupPercent: Decimal
    /// Fraction on both wire and model, unlike EstimateLineItem's UI percentage.
    let taxRate: Decimal
    let itemType: String?
    let createdAt: Date
    let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, category, name, description, quantity, unit
        case unitCost = "unit_cost", markupPercent = "markup_percent", taxRate = "tax_rate", itemType = "item_type"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    func editForm(locale: Locale = .current) -> EstimateLineItemForm {
        EstimateLineItemForm(item: EstimateLineItem(
            id: id, estimateId: "", parentLineItemId: nil, sourceMaterialSuggestionId: nil,
            category: category, itemType: itemType, name: name, description: description,
            quantity: quantity, unit: unit, unitCost: unitCost, markupPercent: markupPercent,
            taxRate: taxRate * 100, lineTotal: 0, sortOrder: 0
        ), locale: locale)
    }
}

struct EstimateLibraryPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
}

struct InstantiateEstimateTemplateRequest: Encodable, Sendable {
    let requestId: UUID
    let projectId: String
    let title: String?
    enum CodingKeys: String, CodingKey { case requestId = "request_id", projectId = "project_id", title }
}

struct SaveEstimateTemplateRequest: Encodable, Sendable {
    let requestId: UUID
    let estimateId: String
    let name: String
    let description: String?
    enum CodingKeys: String, CodingKey { case requestId = "request_id", estimateId = "estimate_id", name, description }
}

struct DuplicateEstimateRequest: Encodable, Sendable {
    let requestId: UUID
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}

struct ApplyEstimateLibraryItemRequest: Encodable, Sendable {
    let requestId: UUID
    let estimateId: String
    enum CodingKeys: String, CodingKey { case requestId = "request_id", estimateId = "estimate_id" }
}

struct SaveEstimateLibraryItemRequest: Encodable, Sendable {
    let requestId: UUID
    let fields: EstimateLineItemEditRequest
    let itemType: String?

    init(requestId: UUID, form: EstimateLineItemForm, itemType: String? = "per_unit", locale: Locale = .current) throws {
        let fields = try form.validatedRequest(locale: locale)
        guard fields.quantity >= Decimal(string: "0.01")!, fields.quantity <= Decimal(string: "99999999.99")!,
              fields.unitCost <= Decimal(string: "9999999999.99")!, fields.markupPercent <= Decimal(string: "999.99")! else {
            throw EstimateEditError.validation("Use a quantity of at least 0.01 and keep price and markup within the supported range (markup up to 999.99%).")
        }
        self.requestId = requestId; self.fields = fields; self.itemType = itemType
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id", category, name, description, quantity, unit
        case unitCost = "unit_cost", markupPercent = "markup_percent", taxRate = "tax_rate", itemType = "item_type"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(fields.category, forKey: .category); try c.encode(fields.name, forKey: .name)
        try c.encode(fields.description, forKey: .description); try c.encode(fields.quantity, forKey: .quantity)
        try c.encode(fields.unit, forKey: .unit); try c.encode(fields.unitCost, forKey: .unitCost)
        try c.encode(fields.markupPercent, forKey: .markupPercent); try c.encode(fields.taxRate, forKey: .taxRate)
        try c.encode(itemType, forKey: .itemType)
    }
}

protocol EstimateLibraryServing: Sendable {
    func templates(query: String, cursor: String?) async throws -> EstimateLibraryPage<EstimateTemplate>
    func items(query: String, cursor: String?) async throws -> EstimateLibraryPage<SavedEstimateLibraryItem>
    func saveTemplate(_ request: SaveEstimateTemplateRequest) async throws -> EstimateTemplate
    func saveItem(_ request: SaveEstimateLibraryItemRequest, itemId: String?) async throws -> SavedEstimateLibraryItem
    func applyItem(id: String, request: ApplyEstimateLibraryItemRequest) async throws -> EstimateLineItem
    func duplicateEstimate(id: String, request: DuplicateEstimateRequest) async throws -> Estimate
    func removeItem(id: String) async throws
    func removeTemplate(id: String) async throws
}

protocol EstimateLibraryFailureClassifying: Error {
    var libraryWriteWasRejected: Bool { get }
}
