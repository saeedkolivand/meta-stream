import Foundation
import Security

/// Where OAuth tokens live. The Keychain in the app; UserDefaults (which conforms) in tests.
public protocol TokenStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func stringArray(forKey key: String) -> [String]?
}

extension UserDefaults: TokenStore {}

public final class KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String = "com.saeedkolivand.metastream") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    public func string(forKey key: String) -> String? {
        var lookup = query(key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public func set(_ value: Any?, forKey key: String) {
        guard let text = value as? String else {
            if value == nil { SecItemDelete(query(key) as CFDictionary) }
            return
        }
        let data = Data(text.utf8)
        let match = query(key)
        let attrs = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    public func removeObject(forKey key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
    public func stringArray(forKey key: String) -> [String]? { nil }
}
