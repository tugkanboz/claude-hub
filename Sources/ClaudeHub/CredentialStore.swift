import CryptoKit
import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case malformedCredential

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return L10n.format(.keychainReadFailed, status)
        case .malformedCredential:
            return L10n.text(.malformedCredential)
        }
    }
}

struct CredentialStore {
    func read(for account: Account) throws -> OAuthCredential {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.serviceName(for: account.configDirectory),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = item as? Data,
              let envelope = try? JSONDecoder().decode(OAuthEnvelope.self, from: data)
        else {
            throw CredentialStoreError.malformedCredential
        }
        return envelope.claudeAiOauth
    }

    static func serviceName(for configDirectory: String) -> String {
        let digest = SHA256.hash(data: Data(configDirectory.utf8))
        let prefix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(prefix)"
    }
}

/// Keeps Claude Code credentials in memory for the lifetime of ClaudeHub.
///
/// macOS may require user approval whenever an app reads another application's
/// Keychain item. Usage refreshes happen every five minutes, so reading the
/// Keychain on every refresh would repeatedly show that prompt. This cache
/// limits normal Keychain access to once per profile per app launch. A reload
/// only happens after Claude Code renews a token or an API request reports that
/// the cached access token is no longer valid.
actor CredentialCache {
    typealias Loader = @Sendable (Account) throws -> OAuthCredential

    private let loader: Loader
    private var values: [String: OAuthCredential] = [:]

    init(loader: @escaping Loader = { account in
        try CredentialStore().read(for: account)
    }) {
        self.loader = loader
    }

    func read(for account: Account) throws -> OAuthCredential {
        if let credential = values[account.configDirectory] {
            return credential
        }
        return try reload(for: account)
    }

    func reload(for account: Account) throws -> OAuthCredential {
        let credential = try loader(account)
        values[account.configDirectory] = credential
        return credential
    }

    func remember(_ credential: OAuthCredential, for account: Account) {
        values[account.configDirectory] = credential
    }

    func remove(for account: Account) {
        values[account.configDirectory] = nil
    }
}
