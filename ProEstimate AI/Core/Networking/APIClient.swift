import Foundation

/// Protocol defining the API client interface.
/// All networking goes through this protocol so the app can swap in
/// `MockAPIClient` for previews and tests without changing view models.
protocol APIClientProtocol {
    /// Execute a request and decode the response body into `T`.
    /// Throws `APIError` on failure.
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T

    /// Execute a request that returns no meaningful body (e.g., DELETE).
    /// Throws `APIError` on failure.
    func request(_ endpoint: APIEndpoint) async throws
}

/// Production API client that communicates with the ProEstimate backend.
/// Handles token injection, response envelope unwrapping, ISO8601 date decoding,
/// snake_case mapping, and automatic token refresh on 401.
final class APIClient: APIClientProtocol {
    /// Shared singleton instance for the app.
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let tokenStore: TokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Single-flight coordinator for token refresh. Dedupes a burst of 401s
    /// so we only issue ONE `/auth/refresh` call when several requests race.
    /// Uses an actor rather than a thread-locking primitive because holding
    /// `NSLock` across `await` is a documented Swift-concurrency deadlock.
    private let refreshCoordinator = RefreshCoordinator()

    /// Callback invoked when token refresh fails and the user must re-authenticate.
    /// Set by the app's auth coordinator.
    var onUnauthorized: (@Sendable () -> Void)?

    init(
        baseURL: String = AppConstants.apiBaseURL,
        session: URLSession? = nil,
        tokenStore: TokenStore = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        // Configure a dedicated URLSession so we can tune timeouts.
        // Request timeout (30s) protects short REST calls; resource timeout (120s)
        // accommodates AI generation polling without hanging forever.
        //
        // We deliberately do NOT set `waitsForConnectivity = true`: that setting
        // makes requests block indefinitely when the device can't reach the
        // server (cold-start Railway container, flaky DNS, offline), which
        // caused the auth-gate splash to hang at launch.
        if let injected = session {
            self.session = injected
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
            config.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: config)
        }

        // Configure encoder with snake_case keys for outbound requests.
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        // Configure decoder with snake_case keys for inbound responses.
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .useDefaultKeys // We use explicit CodingKeys
        // Custom date strategy: handles ISO8601 with and without fractional seconds.
        // JavaScript's toISOString() always produces fractional seconds (e.g. ".000Z")
        // which the default .iso8601 strategy cannot parse.
        let isoWithFrac = ISO8601DateFormatter()
        isoWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoWithout = ISO8601DateFormatter()
        isoWithout.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoWithFrac.date(from: dateString) {
                return date
            }
            if let date = isoWithout.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        self.decoder = dec
    }

    // MARK: - APIClientProtocol

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await performRequest(endpoint)
        return try decodeSuccess(data: data)
    }

    func request(_ endpoint: APIEndpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    // MARK: - Internal

    /// Build a URLRequest, execute it, and return the raw response data.
    /// Handles 401 by attempting a single token refresh before failing.
    private func performRequest(_ endpoint: APIEndpoint) async throws -> Data {
        let urlRequest = try buildRequest(endpoint)
        let (data, response) = try await execute(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network("Invalid response type")
        }

        // Handle 401 with token refresh retry.
        if httpResponse.statusCode == 401, endpoint.requiresAuth {
            let didRefresh = await attemptTokenRefresh()
            if didRefresh {
                // Rebuild the request with the new token and retry once.
                let retryRequest = try buildRequest(endpoint)
                let (retryData, retryResponse) = try await execute(retryRequest)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw APIError.network("Invalid response type on retry")
                }
                return try handleHTTPResponse(retryHTTP, data: retryData)
            } else {
                onUnauthorized?()
                throw APIError.unauthorized
            }
        }

        return try handleHTTPResponse(httpResponse, data: data)
    }

    /// Execute a URLRequest and map transport errors to `APIError.network`.
    private func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// Process the HTTP status code and return data on success, or throw on error.
    private func handleHTTPResponse(_ response: HTTPURLResponse, data: Data) throws -> Data {
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 400...499:
            throw try decodeError(data: data)
        case 500...599:
            throw try decodeError(data: data)
        default:
            throw APIError.unknown("Unexpected status code: \(response.statusCode)")
        }
    }

    /// Build a URLRequest from an `APIEndpoint`.
    private func buildRequest(_ endpoint: APIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + endpoint.path) else {
            throw APIError.network("Invalid URL: \(baseURL + endpoint.path)")
        }

        if let queryItems = endpoint.queryItems {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.network("Could not construct URL from components")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Inject bearer token for authenticated endpoints.
        if endpoint.requiresAuth, let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode the request body if present.
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encodeBody(body)
        }

        return request
    }

    /// Encode an `Encodable` body using a type-erased wrapper.
    private func encodeBody(_ body: any Encodable) throws -> Data {
        try encoder.encode(AnyEncodable(body))
    }

    /// Decode a success envelope and return the inner `data` payload.
    /// Preserves `DecodingError` context so support can diagnose schema mismatches.
    private func decodeSuccess<T: Decodable>(data: Data) throws -> T {
        do {
            let envelope = try decoder.decode(APISuccessEnvelope<T>.self, from: data)
            return envelope.data
        } catch let decodingError as DecodingError {
            throw APIError.decoding(Self.describe(decodingError, type: T.self))
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// Produce a concise, developer-friendly description of a `DecodingError`
    /// that identifies the exact key path and failure reason.
    private static func describe<T>(_ error: DecodingError, type: T.Type) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(T.self): type mismatch at '\(path)' — expected \(type). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(T.self): missing \(type) at '\(path)'. \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(T.self): missing key '\(key.stringValue)' at '\(path)'."
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(T.self): corrupted data at '\(path)'. \(context.debugDescription)"
        @unknown default:
            return "\(T.self): \(error.localizedDescription)"
        }
    }

    /// Decode an error envelope and return the appropriate `APIError`.
    private func decodeError(data: Data) throws -> APIError {
        do {
            let envelope = try decoder.decode(APIErrorEnvelope.self, from: data)

            // If the error includes a paywall payload, surface it as a paywall error.
            if let paywall = envelope.error.paywall {
                return .paywall(paywall)
            }

            // If the error includes field-level validation errors, surface them.
            if let fields = envelope.error.fieldErrors, !fields.isEmpty {
                return .validation(fields: fields)
            }

            return .server(code: envelope.error.code, message: envelope.error.message)
        } catch {
            return .unknown("Failed to decode error response")
        }
    }

    /// Attempt to refresh the access token using the stored refresh token.
    /// Returns `true` if the refresh succeeded and new tokens are stored.
    ///
    /// Single-flight via `RefreshCoordinator` — concurrent 401s wait on the
    /// same in-flight task instead of each making their own refresh call.
    private func attemptTokenRefresh() async -> Bool {
        guard tokenStore.refreshToken != nil else { return false }
        return await refreshCoordinator.refresh { [weak self] in
            guard let self else { return false }
            return await self.performRefresh()
        }
    }

    /// The actual HTTP work for a refresh. Called at most once at a time by
    /// `RefreshCoordinator`.
    private func performRefresh() async -> Bool {
        guard let refreshToken = tokenStore.refreshToken else { return false }

        do {
            let endpoint = APIEndpoint.authRefreshToken(refreshToken: refreshToken)
            let request = try buildRequest(endpoint)
            let (data, response) = try await execute(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return false
            }

            let tokenResponse: TokenRefreshResponse = try decodeSuccess(data: data)
            tokenStore.storeTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken
            )
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Refresh Coordinator

/// Serializes token-refresh attempts so a burst of 401s only triggers one
/// `/auth/refresh` call. All concurrent callers await the same `Task<Bool, Never>`.
private actor RefreshCoordinator {
    private var inFlight: Task<Bool, Never>?

    func refresh(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await operation() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

// MARK: - Supporting Types

/// Response from the token refresh endpoint.
private struct TokenRefreshResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// Type-erased wrapper for encoding arbitrary `Encodable` values.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
