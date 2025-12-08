import Foundation
import LocalAuthentication
import Security

enum PasswordKeychainError: Error {
    case unexpectedStatus(OSStatus)
    case passwordNotFound
}

struct PasswordKeychain {
    private static let service = "eu.flareapps.prism.passwords"

    static func savePassword(_ password: String, for key: String) throws {
        let passwordData = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let update: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PasswordKeychainError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw PasswordKeychainError.unexpectedStatus(status)
        }
    }

    static func loadPassword(for key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw PasswordKeychainError.passwordNotFound
        }

        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw PasswordKeychainError.unexpectedStatus(status)
        }

        return password
    }

    /// Ask macOS to authenticate the current user (Touch ID or password) before filling a password.
    static func authenticateForFilling(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        // Check if device-owner authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch {
            return false
        }
    }
}


