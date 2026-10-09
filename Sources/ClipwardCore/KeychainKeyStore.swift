import Foundation
import Security

/// Supplies the symmetric key used to encrypt history at rest.
public protocol EncryptionKeyProvider {
    func key() throws -> Data
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Keeps a random encryption key as a generic password in the user's login keychain,
/// creating it on first use. The key never touches disk outside the keychain.
public final class KeychainKeyStore: EncryptionKeyProvider {
    private let service: String
    private let account: String
    private let length: Int

    public init(service: String, account: String = "history-encryption-key", length: Int = AuthenticatedCipher.keyLength) {
        self.service = service
        self.account = account
        self.length = length
    }

    /// Returns the stored key, generating and storing a new one if none exists.
    public func key() throws -> Data {
        if let existing = try read(), existing.count == length { return existing }
        let fresh = try AuthenticatedCipher.randomBytes(count: length)
        try store(fresh)
        return fresh
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    private func store(_ key: Data) throws {
        SecItemDelete(baseQuery as CFDictionary) // drop a malformed leftover, if any
        var attributes = baseQuery
        attributes[kSecValueData as String] = key
        attributes[kSecAttrLabel as String] = "Clipward history encryption key"
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
