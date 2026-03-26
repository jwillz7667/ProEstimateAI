import Foundation

/// Generic success response envelope matching the backend contract:
/// `{ ok: true, data: T, meta?: { ... } }`.
/// All successful API responses are decoded through this wrapper.
struct APISuccessEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
    let meta: APIResponseMeta?
}

/// Error response envelope matching the backend contract:
/// `{ ok: false, error: { code, message, ... } }`.
/// All error API responses are decoded through this wrapper.
struct APIErrorEnvelope: Decodable {
    let ok: Bool
    let error: ErrorBody
    let meta: APIResponseMeta?

    struct ErrorBody: Decodable {
        let code: String
        let message: String
        let fieldErrors: [String: [String]]?
        let retryable: Bool?
        let paywall: PaywallDecision?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case fieldErrors = "field_errors"
            case retryable
            case paywall
        }
    }
}

/// Metadata returned in all API responses for tracing and pagination.
struct APIResponseMeta: Decodable, Sendable {
    let requestId: String?
    let timestamp: String?
    let pagination: Pagination?

    struct Pagination: Decodable, Sendable {
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case nextCursor = "next_cursor"
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case timestamp
        case pagination
    }
}
