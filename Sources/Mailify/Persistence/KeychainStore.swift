import Foundation
import Security

/// Thin wrapper over Security-framework Keychain Services for storing OAuth
/// tokens and the Anthropic API key. Never store secrets in AppStore/JSON.
enum KeychainStore {
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        guard addStatus == errSecDuplicateItem else {
            return false
        }
        // An item already exists. This used to be handled by deleting first
        // and always re-adding, but that silently broke across app rebuilds:
        // this app is ad-hoc code-signed (no stable Team ID), so every
        // rebuild is a different signing identity as far as Keychain ACLs
        // are concerned. Confirmed empirically — a differently-signed
        // rebuild's SecItemDelete on another build's item fails with
        // errSecNoAccessForItem (-25244), so the following SecItemAdd then
        // fails as errSecDuplicateItem (-25299): the item was never actually
        // replaced, but the caller had no way to know. SecItemUpdate has
        // looser cross-signature semantics and succeeds where delete+add
        // doesn't, so it's the reliable upsert path here.
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        return updateStatus == errSecSuccess
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Well-known Keychain service/account identifiers used across the app.
enum KeychainKeys {
    static let anthropicService = "com.hari.mailify.anthropic"
    static let anthropicAccount = "api-key"

    static func gmailAccessTokenService(email: String) -> String { "com.hari.mailify.gmail.\(email).accessToken" }
    static func gmailRefreshTokenService(email: String) -> String { "com.hari.mailify.gmail.\(email).refreshToken" }
    static func gmailExpiryService(email: String) -> String { "com.hari.mailify.gmail.\(email).expiresAt" }
    static let gmailAccount = "token"
}
