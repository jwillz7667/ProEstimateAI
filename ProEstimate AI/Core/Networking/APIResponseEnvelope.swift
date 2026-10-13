import Foundation

/// A decoded list page and the cursor required to fetch the remaining records.
struct APIPage<Item: Decodable> {
    let items: [Item]
    let nextCursor: String?
}

/// Walk cursor pages sequentially, deduplicating rows changed during the walk.
/// A malformed repeated cursor fails explicitly instead of looping forever.
enum APIPageCollector {
    static func collect<Item: Decodable & Identifiable>(
        fetch: (String?) async throws -> APIPage<Item>
    ) async throws -> [Item] {
        var items: [Item] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<Item.ID> = []
        repeat {
            try Task.checkCancellation()
            let page = try await fetch(cursor)
            items.append(contentsOf: page.items.filter { seenIDs.insert($0.id).inserted })
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw APIError.decoding("The server returned a repeated pagination cursor. Please refresh the list.")
            }
        } while cursor != nil
        return items
    }
}

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
