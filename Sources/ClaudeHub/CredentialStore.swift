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

struct CredentialPersistence: Sendable {
    var read: @Sendable (Account) throws -> OAuthCredential?
    var write: @Sendable (OAuthCredential, Account) throws -> Void
    var remove: @Sendable (Account) throws -> Void

    static let keychain = CredentialPersistence(
        read: { try HubCredentialStore().read(for: $0) },
        write: { try HubCredentialStore().write($0, for: $1) },
        remove: { try HubCredentialStore().remove(for: $0) }
    )
}

struct HubCredentialStore {
    static let service = "com.tugkanboz.claudehub.credentials"

    private func query(for account: Account) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service,
         kSecAttrAccount: account.id.uuidString]
    }

    func read(for account: Account) throws -> OAuthCredential? {
        var query = query(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = item as? Data else { throw CredentialStoreError.malformedCredential }
        return try JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    func write(_ credential: OAuthCredential, for account: Account) throws {
        let data = try JSONEncoder().encode(credential)
        let query = query(for: account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    func remove(for account: Account) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}

actor CredentialCache {
    typealias Loader = @Sendable (Account) throws -> OAuthCredential

    private let loader: Loader
    private let persistence: CredentialPersistence?
    private var values: [UUID: OAuthCredential] = [:]

    init(loader: @escaping Loader = { account in
        try CredentialStore().read(for: account)
    }, persistence: CredentialPersistence? = nil) {
        self.loader = loader
        self.persistence = persistence
    }

    func read(for account: Account) throws -> OAuthCredential {
        if let credential = values[account.id] {
            return credential
        }
        if let credential = try persistence?.read(account) {
            values[account.id] = credential
            return credential
        }
        return try reload(for: account)
    }

    func reload(for account: Account) throws -> OAuthCredential {
        let credential = try loader(account)
        remember(credential, for: account)
        return credential
    }

    func remember(_ credential: OAuthCredential, for account: Account) {
        values[account.id] = credential
        do { try persistence?.write(credential, account) } catch {
            AppLogger.write("[warn] Could not persist ClaudeHub credential; keeping it in memory")
        }
    }

    func remove(for account: Account) throws {
        values[account.id] = nil
        try persistence?.remove(account)
    }
}
