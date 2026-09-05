import Foundation
import Security

/// Minimal macOS Keychain wrapper for OAuth tokens. UserDefaults is a plain
/// plist file on disk — readable by anything running as the same user — so
/// tokens live here instead, where the OS encrypts them at rest.
enum KeychainStore {
    private static let service = "com.missting.oauth"

    // Every CI-built release is ad-hoc signed (no paid Apple Developer ID),
    // so the code signature — and therefore Keychain's per-app trust — differs
    // on every single release. Without this, each auto-update makes macOS
    // treat the "new" Missting as untrusted for items the "old" Missting
    // created, and pops the scary "wants to access key in your keychain,
    // enter your password" system dialog. kSecUseAuthenticationUIFail makes
    // the call fail silently instead of ever prompting — the app then just
    // treats it as "no stored token" and falls back to a normal sign-in
    // screen, which is a far better experience than a password dialog.
    private static let noPromptOption: [String: Any] = [
        kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
    ]

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query.merging(noPromptOption) { $1 } as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String]      = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs.merging(noPromptOption) { $1 } as CFDictionary, nil)
        // If a stale, differently-signed item already exists and can't be
        // silently overwritten, drop it so the next attempt starts clean
        // rather than leaving the new token unsaved.
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            SecItemDelete(query as CFDictionary)
            SecItemAdd(attrs.merging(noPromptOption) { $1 } as CFDictionary, nil)
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query.merging(noPromptOption) { $1 } as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query.merging(noPromptOption) { $1 } as CFDictionary)
    }
}
