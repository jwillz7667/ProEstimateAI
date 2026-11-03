import Foundation

/// Server-calculated next actions across the entire workspace. These counts
/// never come from Home's small recent-project page.
struct DashboardAttention: Codable, Sendable {
    let generatedAt: Date
    let followUpAfterDays: Int
    let groups: [DashboardAttentionGroup]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case followUpAfterDays = "follow_up_after_days"
        case groups
    }

    var totalCount: Int { groups.reduce(0) { $0 + $1.count } }
}

struct DashboardMoney: Codable, Hashable, Sendable {
    let currencyCode: String
    let amount: Decimal

    enum CodingKeys: String, CodingKey {
        case currencyCode = "currency_code"
        case amount
    }

    init(currencyCode: String, amount: Decimal) {
        self.currencyCode = currencyCode
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decode(String.self, forKey: .currencyCode)
        if let decimal = try? values.decode(Decimal.self, forKey: .amount) {
            amount = decimal
        } else {
            let text = try values.decode(String.self, forKey: .amount)
            guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else {
                throw DecodingError.dataCorruptedError(forKey: .amount, in: values, debugDescription: "Invalid monetary amount")
            }
            amount = decimal
        }
    }

    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }
}

struct DashboardAttentionGroup: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case overdueInvoice = "overdue_invoice"
        case changesRequested = "changes_requested"
        case approvedEstimate = "approved_estimate"
        case unansweredProposal = "unanswered_proposal"
        case draftEstimate = "draft_estimate"

        var title: String {
            switch self {
            case .overdueInvoice: "Follow up overdue payment"
            case .changesRequested: "Review requested changes"
            case .approvedEstimate: "Invoice approved work"
            case .unansweredProposal: "Follow up a proposal"
            case .draftEstimate: "Finish an estimate"
            }
        }

        var icon: String {
            switch self {
            case .overdueInvoice: "exclamationmark.circle"
            case .changesRequested: "text.bubble"
            case .approvedEstimate: "checkmark.seal"
            case .unansweredProposal: "paperplane"
            case .draftEstimate: "square.and.pencil"
            }
        }

        var countLabel: String {
            switch self {
            case .overdueInvoice: "overdue"
            case .changesRequested: "need a revision"
            case .approvedEstimate: "ready to invoice"
            case .unansweredProposal: "awaiting a reply"
            case .draftEstimate: "drafts"
            }
        }
    }

    struct Target: Codable, Sendable {
        let documentId: String
        let projectId: String
        let documentNumber: String
        let projectTitle: String
        let clientName: String?

        enum CodingKeys: String, CodingKey {
            case documentId = "document_id"
            case projectId = "project_id"
            case documentNumber = "document_number"
            case projectTitle = "project_title"
            case clientName = "client_name"
        }
    }

    let kind: Kind
    let count: Int
    let amounts: [DashboardMoney]
    let target: Target

    var id: Kind { kind }
    var summary: String {
        let money = amounts.map(\.formatted).joined(separator: " + ")
        return money.isEmpty ? "\(count) \(kind.countLabel)" : "\(count) \(kind.countLabel) · \(money)"
    }
}
