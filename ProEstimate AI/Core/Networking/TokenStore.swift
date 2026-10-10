import Foundation
import os
import Security

/// Keychain-backed storage for access and refresh tokens.
/// Uses the iOS Security framework directly — no third-party dependencies.
/// Tokens are stored with `kSecAttrAccessibleAfterFirstUnlock` for
/// background refresh support.
final class TokenStore: Sendable {
    /// Shared instance used throughout the app.
    static let shared = TokenStore()

    private let serviceName: String
    // Keychain operations are synchronous. Hold this lock only around local
    // reads/writes, never across an await. Its UUID identifies a login session
    // and changes on login/logout, but not on ordinary token rotation.
    private let sessionLock = OSAllocatedUnfairLock(initialState: UUID())

    struct SessionSnapshot: Sendable {
        let id: UUID
        let accessToken: String?
        let refreshToken: String?
    }

    var sessionSnapshot: SessionSnapshot {
        sessionLock.withLock { id in
            SessionSnapshot(
                id: id,
                accessToken: read(key: AppConstants.keychainAccessTokenKey),
                refreshToken: read(key: AppConstants.keychainRefreshTokenKey)
            )
        }
    }

    var sessionIdentifier: UUID {
        sessionLock.withLock { $0 }
    }
    /// Logger for keychain operations. SECURITY: never log the token values
    /// themselves — only opaque status codes and key identifiers.
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "TokenStore")

    init(serviceName: String = AppConstants.keychainServiceName) {
        self.serviceName = serviceName
    }

    // MARK: - Access Token

    /// The current access token, or nil if not stored.
    var accessToken: String? {
        sessionLock.withLock { _ in read(key: AppConstants.keychainAccessTokenKey) }
    }

    /// The current refresh token, or nil if not stored.
    var refreshToken: String? {
        sessionLock.withLock { _ in read(key: AppConstants.keychainRefreshTokenKey) }
    }

    /// Store both tokens after a successful login or token refresh.
    /// - Parameters:
    ///   - accessToken: The JWT access token.
    ///   - refreshToken: The refresh token for obtaining new access tokens.
    func storeTokens(accessToken: String, refreshToken: String) {
        sessionLock.withLock { id in
            id = UUID()
            save(key: AppConstants.keychainAccessTokenKey, value: accessToken)
            save(key: AppConstants.keychainRefreshTokenKey, value: refreshToken)
        }
    }

    /// Refresh can only replace the exact session and token that started it.
    /// The comparison and both writes are atomic with respect to logout/login.
    func replaceTokens(
        for session: SessionSnapshot,
        accessToken: String,
        refreshToken: String
    ) -> Bool {
        sessionLock.withLock { id in
            guard id == session.id,
                  read(key: AppConstants.keychainRefreshTokenKey) == session.refreshToken else { return false }
            save(key: AppConstants.keychainAccessTokenKey, value: accessToken)
            save(key: AppConstants.keychainRefreshTokenKey, value: refreshToken)
            return true
        }
    }

    /// Atomically invalidate the session, clear local credentials, and return
    /// the old refresh token so logout can revoke it without using a new login.
    @discardableResult
    func clearTokens() -> String? {
        sessionLock.withLock { id in
            let refreshToken = read(key: AppConstants.keychainRefreshTokenKey)
            id = UUID()
            delete(key: AppConstants.keychainAccessTokenKey)
            delete(key: AppConstants.keychainRefreshTokenKey)
            return refreshToken
        }
    }

    /// Whether any access token is currently stored.
    var hasTokens: Bool {
        accessToken != nil
    }

    // MARK: - Keychain Operations

    /// Save a string value to the Keychain.
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first to avoid duplicate errors.
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Log only opaque status + key label (never the token value itself)
            // so nothing sensitive can leak into crash reports or device logs.
            Self.logger.error("Keychain save failed (OSStatus=\(status))")
        }
    }

    /// Read a string value from the Keychain.
    private func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
