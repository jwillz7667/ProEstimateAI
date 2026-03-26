import Foundation

/// Unified error type for all API interactions.
/// Covers transport, decoding, server, auth, and monetization errors.
/// View models should switch on these cases to determine the correct user-facing behavior.
enum APIError: Error, Equatable, Sendable {
    /// Network connectivity or transport failure.
    case network(String)

    /// Failed to decode the response body.
    case decoding(String)

    /// Server returned an error with a machine-readable code and human message.
    case server(code: String, message: String)

    /// The request requires authentication and the current tokens are invalid.
    case unauthorized

    /// The action is blocked by monetization — present the paywall.
    case paywall(PaywallDecision)

    /// Request validation failed with per-field errors.
    case validation(fields: [String: [String]])

    /// An unexpected error that does not fit other categories.
    case unknown(String)

    // MARK: - Equatable

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let a), .network(let b)):
            return a == b
        case (.decoding(let a), .decoding(let b)):
            return a == b
        case (.server(let codeA, let msgA), .server(let codeB, let msgB)):
            return codeA == codeB && msgA == msgB
        case (.unauthorized, .unauthorized):
            return true
        case (.paywall(let a), .paywall(let b)):
            return a == b
        case (.validation(let a), .validation(let b)):
            return a == b
        case (.unknown(let a), .unknown(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - LocalizedError

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .network(let detail):
            return "Network error: \(detail)"
        case .decoding(let detail):
            return "Failed to parse response: \(detail)"
        case .server(_, let message):
            return message
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .paywall:
            return "This feature requires a Pro subscription."
        case .validation(let fields):
            let messages = fields.flatMap { $0.value }
            return messages.joined(separator: ". ")
        case .unknown(let detail):
            return "An unexpected error occurred: \(detail)"
        }
    }
}

// MARK: - Convenience

extension APIError {
    /// Whether the user should be prompted to retry.
    var isRetryable: Bool {
        switch self {
        case .network:
            return true
        case .server:
            return false
        case .unauthorized, .paywall, .validation, .decoding, .unknown:
            return false
        }
    }

    /// Whether this error should trigger a sign-out flow.
    var requiresReauth: Bool {
        self == .unauthorized
    }
}
