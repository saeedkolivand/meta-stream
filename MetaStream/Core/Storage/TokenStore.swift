import Foundation
import Security

protocol TokenStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func stringArray(forKey key: String) -> [String]?
}

final class UserDefaultsTokenStore: TokenStore {
    private let d: UserDefaults
    init(_ d: UserDefaults = .standard) { self.d = d }
    func string(forKey key: String) -> String? { d.string(forKey: key) }
    func set(_ value: Any?, forKey key: String) { d.set(value, forKey: key) }
    func removeObject(forKey key: String) { d.removeObject(forKey: key) }
    func stringArray(forKey key: String) -> [String]? { d.stringArray(forKey: key) }
}

extension UserDefaults: TokenStore {}

final class KeychainTokenStore: TokenStore {
    private let service: String
    init(service: String = "com.saeedkolivand.metastream") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    func string(forKey key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func set(_ value: Any?, forKey key: String) {
        guard let s = value as? String else {
            if value == nil { SecItemDelete(query(key) as CFDictionary) }
            return
        }
        let data = Data(s.utf8)
        let q = query(key)
        let attrs = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    func removeObject(forKey key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
    func stringArray(forKey key: String) -> [String]? { nil }
}
