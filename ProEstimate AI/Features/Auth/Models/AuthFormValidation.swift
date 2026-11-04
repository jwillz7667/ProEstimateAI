import Foundation

/// Mirrors the server's public signup rules so invalid forms fail before a request.
enum AuthFormValidation {
    static func isValidEmail(_ email: String) -> Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:[A-Za-z0-9_'+\-]+\.)*[A-Za-z0-9_'+\-]*[A-Za-z0-9_+-]@(?:[A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$"#
        return value.utf16.count <= 255 && value.range(of: pattern, options: .regularExpression) != nil
    }

    static func passwordMessage(_ password: String) -> String? {
        guard password.utf16.count >= 8 else { return "Use at least 8 characters." }
        guard password.utf8.count <= 72 else { return "Password is too long. Use fewer characters or emoji." }
        guard password.range(of: #"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$"#, options: .regularExpression) != nil else {
            return "Include an uppercase letter, a lowercase letter, and a number."
        }
        return nil
    }

    static func isValidFullName(_ fullName: String) -> Bool {
        let length = fullName.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        return (2...100).contains(length)
    }
}
