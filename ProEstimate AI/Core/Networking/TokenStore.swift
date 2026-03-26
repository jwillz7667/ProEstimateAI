import Foundation
import Security

/// Keychain-backed storage for access and refresh tokens.
/// Uses the iOS Security framework directly — no third-party dependencies.
/// Tokens are stored with `kSecAttrAccessibleAfterFirstUnlock` for
/// background refresh support.
final class TokenStore: Sendable {
    /// Shared instance used throughout the app.
    static let shared = TokenStore()

    private let serviceName: String

    init(serviceName: String = AppConstants.keychainServiceName) {
        self.serviceName = serviceName
    }

    // MARK: - Access Token

    /// The current access token, or nil if not stored.
    var accessToken: String? {
        get { read(key: AppConstants.keychainAccessTokenKey) }
    }

    /// The current refresh token, or nil if not stored.
    var refreshToken: String? {
        get { read(key: AppConstants.keychainRefreshTokenKey) }
    }

    /// Store both tokens after a successful login or token refresh.
    /// - Parameters:
    ///   - accessToken: The JWT access token.
    ///   - refreshToken: The refresh token for obtaining new access tokens.
    func storeTokens(accessToken: String, refreshToken: String) {
        save(key: AppConstants.keychainAccessTokenKey, value: accessToken)
        save(key: AppConstants.keychainRefreshTokenKey, value: refreshToken)
    }

    /// Remove all stored tokens. Called on sign-out.
    func clearTokens() {
        delete(key: AppConstants.keychainAccessTokenKey)
        delete(key: AppConstants.keychainRefreshTokenKey)
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
            print("[TokenStore] Failed to save \(key): \(status)")
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
