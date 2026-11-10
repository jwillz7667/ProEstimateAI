import CryptoKit
import Foundation
import Security

/// Per-attempt proof shared by the authorization request and our token verifier.
enum OAuthRequestSecurity {
    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func nonceHash(_ rawNonce: String) -> String {
        SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
