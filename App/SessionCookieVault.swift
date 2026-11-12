import Foundation
import Security
import WebKit

// The portal's tab storage belongs to this app's WebKit session. Preserve it in
// Keychain so a headless process can resume the same portal tab after app exit.
struct PortalSessionVault {
    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.gteijeiro.PersonalDataWidget.portalTab",
         kSecAttrAccount as String: "mipersonal.personal.com.ar"]
    }

    func load() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ json: String) {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              !values.isEmpty else { return }
        let status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    func clear() { _ = SecItemDelete(identity as CFDictionary) }
}

// Stores only this app's session cookies for Personal. The widget never accesses
// this Keychain item, and no cookie value is written to UserDefaults or logs.
struct SessionCookieVault {
    private let service = "com.gteijeiro.PersonalDataWidget.webSession"
    private let account = "personal.com.ar"

    func load() -> [HTTPCookie] {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let records = try? JSONDecoder().decode([StoredSessionCookie].self, from: data)
        else { return [] }
        return records.compactMap(\.cookie)
    }

    func save(_ cookies: [HTTPCookie]) {
        let records = cookies.compactMap(StoredSessionCookie.init)
        guard !records.isEmpty,
              let data = try? JSONEncoder().encode(records) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    func clear() {
        _ = SecItemDelete(identity as CFDictionary)
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

// The email address is a local preference. Only its password is stored here.
struct LoginPasswordVault {
    private let service = "com.gteijeiro.PersonalDataWidget.emailPassword"
    private let account = "primary"

    func load() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ password: String) -> Bool {
        guard !password.isEmpty, let data = password.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        _ = SecItemDelete(identity as CFDictionary)
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

private struct StoredSessionCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isHTTPOnly: Bool
    let isSecure: Bool
    let sameSite: String?

    init?(_ cookie: HTTPCookie) {
        let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard cookie.isSessionOnly, cookie.isSecure,
              host == "personal.com.ar" || host.hasSuffix(".personal.com.ar")
        else { return nil }
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        isHTTPOnly = cookie.isHTTPOnly
        isSecure = cookie.isSecure
        sameSite = cookie.sameSitePolicy?.rawValue
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[HTTPCookiePropertyKey("SameSite")] = sameSite }
        return HTTPCookie(properties: properties)
    }
}
