import Foundation
import Security

public protocol SecretStore: Sendable {
    func loadSecret(account: String) throws -> String?
    func saveSecret(_ secret: String, account: String) throws
    func loadOrCreateSecret(account: String) throws -> String
}

public enum SecretStoreError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode secret."
        case .decodingFailed:
            return "Failed to decode secret."
        case let .keychain(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "com.myclash.controller") {
        self.service = service
    }

    public func loadSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychain(status)
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.decodingFailed
        }
        return secret
    }

    public func saveSecret(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychain(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychain(addStatus)
        }
    }

    public func loadOrCreateSecret(account: String) throws -> String {
        if let existing = try loadSecret(account: account) {
            return existing
        }
        let secret = Self.generateSecret()
        try saveSecret(secret, account: account)
        return secret
    }

    public static func generateSecret(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String]
    private let lock = NSLock()

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func loadSecret(account: String) throws -> String? {
        lock.withLock {
            values[account]
        }
    }

    public func saveSecret(_ secret: String, account: String) throws {
        lock.withLock {
            values[account] = secret
        }
    }

    public func loadOrCreateSecret(account: String) throws -> String {
        lock.withLock {
            if let existing = values[account] {
                return existing
            }
            let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            values[account] = secret
            return secret
        }
    }
}
