import Foundation

struct JobCostEntry: Codable, Identifiable, Sendable {
    let id: String
    let projectId: String
    let requestId: String
    let category: String
    let description: String
    let amount: Decimal
    let currencyCode: String
    let laborHours: Decimal?
    let hourlyRate: Decimal?
    let recordedAt: Date
    let createdAt: Date
    let voidedAt: Date?
    let receiptFilename: String?
    let receiptMimeType: String?

    enum CodingKeys: String, CodingKey {
        case id, category, description, amount
        case projectId = "project_id", requestId = "request_id", currencyCode = "currency_code"
        case laborHours = "labor_hours", hourlyRate = "hourly_rate", recordedAt = "recorded_at"
        case createdAt = "created_at", voidedAt = "voided_at"
        case receiptFilename = "receipt_filename", receiptMimeType = "receipt_mime_type"
    }
}

struct JobCostPage: Decodable, Sendable {
    let items: [JobCostEntry]
    let nextCursor: String?
    let summary: JobCostSummary
    enum CodingKeys: String, CodingKey { case items, summary; case nextCursor = "next_cursor" }
}

struct JobCostSummary: Decodable, Sendable {
    let currencyCode: String
    let estimateNumber: String?
    let estimateStatus: String?
    let quoteBeforeTax: Decimal?
    let estimatedItemCost: Decimal?
    let recordedCost: Decimal
    let quoteLessRecordedCost: Decimal?
    let costsByCurrency: [CurrencyCosts]
    enum CodingKeys: String, CodingKey {
        case currencyCode = "currency_code", estimateNumber = "estimate_number", estimateStatus = "estimate_status"
        case quoteBeforeTax = "quote_before_tax", estimatedItemCost = "estimated_item_cost", recordedCost = "recorded_cost"
        case quoteLessRecordedCost = "quote_less_recorded_cost", costsByCurrency = "costs_by_currency"
    }
    struct CurrencyCosts: Decodable, Identifiable, Sendable {
        let currencyCode: String
        let materials: Decimal
        let labor: Decimal
        let other: Decimal
        let total: Decimal
        var id: String { currencyCode }
        enum CodingKeys: String, CodingKey { case materials, labor, other, total; case currencyCode = "currency_code" }
    }
}

struct JobCostRequest: Codable, Equatable, Sendable {
    let requestId: String
    let category: String
    let description: String
    let amount: Decimal?
    let currencyCode: String
    let laborHours: Decimal?
    let hourlyRate: Decimal?
    let recordedAt: Date
    enum CodingKeys: String, CodingKey {
        case category, description, amount
        case requestId = "request_id", currencyCode = "currency_code", laborHours = "labor_hours"
        case hourlyRate = "hourly_rate", recordedAt = "recorded_at"
    }
}

struct JobCostDraft: Equatable, Sendable {
    var category = "materials"
    var description = ""
    var amount = ""
    var currencyCode = "USD"
    var useHours = false
    var laborHours = ""
    var hourlyRate = ""
    var recordedAt = Date()

    init() {}

    init(request: JobCostRequest, locale: Locale = .current) {
        category = request.category
        description = request.description
        amount = request.amount.map { Self.input($0, locale: locale) } ?? ""
        currencyCode = request.currencyCode
        useHours = request.laborHours != nil
        laborHours = request.laborHours.map { Self.input($0, locale: locale) } ?? ""
        hourlyRate = request.hourlyRate.map { Self.input($0, locale: locale) } ?? ""
        recordedAt = request.recordedAt
    }

    var validationMessage: String? {
        let name = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.utf16.count > 500 { return "Describe the cost in 1–500 characters." }
        if !["materials", "labor", "other"].contains(category) { return "Choose a cost category." }
        if currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil { return "Choose a currency." }
        if !recordedAt.timeIntervalSince1970.isFinite || recordedAt > Date().addingTimeInterval(86_400) { return "Choose a cost date that isn't in the future." }
        if category == "labor" && useHours {
            guard let hours = Self.positiveMoney(laborHours), hours <= 100_000,
                  let rate = Self.positiveMoney(hourlyRate), hours * rate <= Decimal(string: "9999999999.99")! else {
                return "Enter valid hours and hourly cost, with at most two decimal places."
            }
        } else if Self.positiveMoney(amount) == nil { return "Enter a positive cost with at most two decimal places." }
        return nil
    }

    func request(id: String) -> JobCostRequest? {
        guard validationMessage == nil, UUID(uuidString: id) != nil else { return nil }
        let usesHours = category == "labor" && useHours
        return JobCostRequest(requestId: id, category: category,
                              description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                              amount: usesHours ? nil : Self.positiveMoney(amount), currencyCode: currencyCode,
                              laborHours: usesHours ? Self.positiveMoney(laborHours) : nil,
                              hourlyRate: usesHours ? Self.positiveMoney(hourlyRate) : nil,
                              recordedAt: Date(timeIntervalSince1970: floor(recordedAt.timeIntervalSince1970)))
    }

    private static func positiveMoney(_ text: String) -> Decimal? {
        guard let value = DecimalFormInput.parse(text), value > 0, value <= Decimal(string: "9999999999.99")!, !value.isNaN else { return nil }
        var source = value, rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded == value ? value : nil
    }

    private static func input(_ value: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }
}

nonisolated struct JobCostReceiptAttachment: Sendable {
    let data: Data
    let mimeType: String
    let filename: String

    var validationMessage: String? {
        guard !data.isEmpty, data.count <= 5_000_000 else { return "Choose a receipt no larger than 5 MB." }
        guard !filename.isEmpty, filename.utf16.count <= 255 else { return "Choose a receipt with a shorter file name." }
        let matches: Bool
        switch mimeType {
        case "application/pdf": matches = data.starts(with: Data("%PDF-".utf8))
        case "image/jpeg": matches = data.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/png": matches = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        default: return "Choose a JPEG, PNG or PDF receipt."
        }
        return matches ? nil : "The receipt contents don't match its file type."
    }
}

enum JobCostError: LocalizedError {
    case invalidResponse
    case invalidJournal
    case validation(String)
    nonisolated var errorDescription: String? {
        switch self {
        case .invalidResponse: "The saved cost couldn't be matched to this project."
        case .invalidJournal: "The pending cost couldn't be recovered safely. Review saved costs before adding another copy."
        case let .validation(message): message
        }
    }
}

struct JobCostPending: Codable, Sendable {
    var schemaVersion = 1
    let scope: EstimateDraftScope
    let projectId: String
    let request: JobCostRequest
    var receiptExpected: Bool? = nil
}

protocol JobCostServing: Sendable {
    func list(projectId: String, cursor: String?, includeVoided: Bool) async throws -> JobCostPage
    func create(projectId: String, request: JobCostRequest) async throws -> JobCostEntry
    func voidEntry(id: String) async throws
    func attachReceipt(id: String, data: Data, mimeType: String, filename: String) async throws
    func receipt(id: String) async throws -> Data
}
