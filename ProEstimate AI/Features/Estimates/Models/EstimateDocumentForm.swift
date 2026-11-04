import Foundation

struct EstimateDocumentForm: Equatable, Sendable {
    var title: String
    var notes: String
    var assumptions: String
    var exclusions: String
    var discount: String
    var hasValidUntil: Bool
    var validUntil: Date

    init(estimate: Estimate, locale: Locale = .current) {
        title = estimate.title ?? ""
        notes = estimate.notes ?? ""
        assumptions = estimate.assumptions ?? ""
        exclusions = estimate.exclusions ?? ""
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        discount = formatter.string(from: estimate.discountAmount as NSDecimalNumber) ?? "0"
        hasValidUntil = estimate.validUntil != nil
        validUntil = estimate.validUntil ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    func validatedRequest(estimate: Estimate, locale: Locale = .current) throws -> EstimateDocumentEditRequest {
        guard estimate.isEditable else { throw EstimateEditError.validation("Create a revision to change a sent estimate.") }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.utf16.count <= 500 else { throw EstimateEditError.validation("Keep the estimate title within 500 characters.") }
        guard notes.utf16.count <= 10000 else { throw EstimateEditError.validation("Keep notes within 10,000 characters.") }
        guard assumptions.utf16.count <= 50000, exclusions.utf16.count <= 50000 else {
            throw EstimateEditError.validation("Keep assumptions and exclusions within 50,000 characters each.")
        }
        guard let amount = DecimalFormInput.parse(discount.isEmpty ? "0" : discount, locale: locale),
              amount >= 0, amount <= Decimal(string: "9999999999.99")! else {
            throw EstimateEditError.validation("Enter a valid nonnegative discount.")
        }
        var original = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 2, .plain)
        guard rounded == amount else { throw EstimateEditError.validation("Discounts support up to two decimal places.") }
        let maximum = estimate.subtotalMaterials + estimate.subtotalLabor + estimate.subtotalOther + estimate.taxAmount
        guard amount <= maximum else { throw EstimateEditError.validation("The discount can't exceed the estimate before discount.") }
        guard !hasValidUntil || validUntil.timeIntervalSince1970.isFinite else {
            throw EstimateEditError.validation("Choose a valid expiration date.")
        }
        return EstimateDocumentEditRequest(
            title: cleanTitle.isEmpty ? nil : cleanTitle,
            notes: Self.optional(notes), assumptions: Self.optional(assumptions), exclusions: Self.optional(exclusions),
            discountAmount: amount, validUntil: hasValidUntil ? validUntil : nil
        )
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Explicit nulls remove cleared fields. Ownership, lifecycle and calculated
/// totals are never editable through this form.
struct EstimateDocumentEditRequest: Encodable, Sendable {
    let title: String?
    let notes: String?
    let assumptions: String?
    let exclusions: String?
    let discountAmount: Decimal
    let validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case title, notes, assumptions, exclusions
        case discountAmount = "discount_amount"
        case validUntil = "valid_until"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(assumptions, forKey: .assumptions)
        try container.encode(exclusions, forKey: .exclusions)
        try container.encode(discountAmount, forKey: .discountAmount)
        try container.encode(validUntil, forKey: .validUntil)
    }
}
