import Foundation
import Security

/// KeychainAccess-compatible error. Status codes match Security.framework.
public enum KeychainError: Error, Sendable {
    case operationNotSupported
    case unexpected(OSStatus)
}

/// Onion ring: Infrastructure / Vendor.
/// KeychainAccess-compatible wrapper used to store the optional local passcode.
/// Immutable service identifier; all mutation goes through the system keychain.
public final class Keychain {
    public let service: String
    public let accessGroup: String?

    public convenience init() {
        self.init(service: Bundle.main.bundleIdentifier ?? "com.mealorbit.orbit")
    }

    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    @discardableResult
    public func set(_ value: String, key: String) throws -> Keychain {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.operationNotSupported
        }
        try remove(key)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
        return self
    }

    public func get(_ key: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func remove(_ key: String) throws -> Keychain {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return self
        }
        throw KeychainError.unexpected(status)
    }

    public subscript(key: String) -> String? {
        get { try? get(key) }
        set {
            if let newValue {
                _ = try? set(newValue, key: key)
            } else {
                _ = try? remove(key)
            }
        }
    }
}
