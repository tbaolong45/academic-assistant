import Foundation
import Security

/// The Moodle key lives only in the login Keychain (generic password, account = site host).
enum Keychain {
    static let service = "com.tbaolong45.academicassistant.moodle"

    private static func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: host]
    }

    static func save(_ secret: String, host: String) -> Bool {
        delete(host: host)
        var q = query(host)
        q[kSecValueData as String] = Data(secret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly // never synced or restored to another Mac
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func read(host: String) -> String? {
        var q = query(host)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(host: String) -> Bool { SecItemDelete(query(host) as CFDictionary) == errSecSuccess }
}

/// The connected site (not secret, so UserDefaults).
enum MoodleAccount {
    static let defaultSite = "https://lms.mbzuai.ac.ae"
    private static let key = "moodleSite"

    static var site: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Stored site + its key, if both exist.
    static func credentials() -> (site: URL, token: String)? {
        guard let s = site, let url = try? Moodle.siteURL(s), let host = url.host(), let token = Keychain.read(host: host) else { return nil }
        return (url, token)
    }
}
