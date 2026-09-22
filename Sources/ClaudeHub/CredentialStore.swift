import CryptoKit
import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case permissionRequired
    case malformedCredential

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return L10n.text(.credentialPermissionRequired)
        case .keychain(let status):
            return L10n.format(.keychainReadFailed, status)
        case .malformedCredential:
            return L10n.text(.malformedCredential)
        }
    }
}

struct CredentialStore {
    func read(for account: Account, interaction: KeychainInteraction = .background) throws -> OAuthCredential {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.serviceName(for: account.configDirectory),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = KeychainAccess.perform(interaction) { SecItemCopyMatching(query as CFDictionary, &item) }
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
    var interactiveWrite: (@Sendable (OAuthCredential, Account) throws -> Void)? = nil

    static let keychain = CredentialPersistence(
        read: { try HubCredentialStore().read(for: $0) },
        write: { try HubCredentialStore().write($0, for: $1) },
        remove: { try HubCredentialStore().remove(for: $0) },
        interactiveWrite: { try HubCredentialStore().write($0, for: $1, interaction: .userInitiated) }
    )
}

struct HubCredentialStore {
    static let service = "com.tugkanboz.claudehub.credentials"

    private struct Entry: Codable {
        let configDirectory: String
        let credential: OAuthCredential
    }

    private func query(for account: Account) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service,
         kSecAttrAccount: account.id.uuidString]
    }

    func read(for account: Account) throws -> OAuthCredential? {
        var query = query(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = KeychainAccess.perform(.background) { SecItemCopyMatching(query as CFDictionary, &item) }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = item as? Data else { throw CredentialStoreError.malformedCredential }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        guard entry.configDirectory == account.configDirectory else { return nil }
        return entry.credential
    }

    func write(_ credential: OAuthCredential, for account: Account, interaction: KeychainInteraction = .background) throws {
        let data = try JSONEncoder().encode(Entry(configDirectory: account.configDirectory, credential: credential))
        let query = query(for: account)
        let status = KeychainAccess.perform(interaction) {
            let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
            guard updated == errSecItemNotFound else { return updated }
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    func remove(for account: Account) throws {
        let status = KeychainAccess.perform(.background) { SecItemDelete(query(for: account) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}

actor CredentialCache {
    typealias Loader = @Sendable (Account) throws -> OAuthCredential

    private let loader: Loader
    private let interactiveLoader: Loader
    private var permissionRequired: Set<UUID> = []
    private let persistence: CredentialPersistence?
    private var values: [UUID: OAuthCredential] = [:]

    init(loader: Loader? = nil, persistence: CredentialPersistence? = nil, interactiveLoader: Loader? = nil) {
        self.loader = loader ?? { try CredentialStore().read(for: $0) }
        self.interactiveLoader = interactiveLoader ?? loader ?? { try CredentialStore().read(for: $0, interaction: .userInitiated) }
        self.persistence = persistence
    }

    func requiresPermission(for account: Account) -> Bool { permissionRequired.contains(account.id) }

    private func recordPermissionFailure(_ error: Error, for account: Account) -> Error {
        guard CredentialStoreError.requiresPermission(error) else { return error }
        if permissionRequired.insert(account.id).inserted {
            AppLogger.write("[warn] Keychain access requires user action for account \(account.id); background access paused")
            let id = account.id
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .credentialPermissionRequired, object: id)
            }
        }
        return CredentialStoreError.permissionRequired
    }

    func authorize(for account: Account) throws {
        do {
            let credential = try interactiveLoader(account)
            if let persistence {
                try (persistence.interactiveWrite ?? persistence.write)(credential, account)
            }
            values[account.id] = credential
            permissionRequired.remove(account.id)
        } catch { throw recordPermissionFailure(error, for: account) }
    }

    func read(for account: Account) throws -> OAuthCredential {
        if let credential = values[account.id] {
            return credential
        }
        guard !requiresPermission(for: account) else { throw CredentialStoreError.permissionRequired }
        do {
            if let credential = try persistence?.read(account) {
                values[account.id] = credential
                return credential
            }
        } catch { throw recordPermissionFailure(error, for: account) }
        return try reload(for: account)
    }

    func reload(for account: Account) throws -> OAuthCredential {
        guard !requiresPermission(for: account) else { throw CredentialStoreError.permissionRequired }
        do {
            let credential = try loader(account)
            remember(credential, for: account)
            return credential
        } catch { throw recordPermissionFailure(error, for: account) }
    }

    func remember(_ credential: OAuthCredential, for account: Account) {
        values[account.id] = credential
        guard !requiresPermission(for: account) else { return }
        do { try persistence?.write(credential, account) } catch {
            _ = recordPermissionFailure(error, for: account)
            AppLogger.write("[warn] Could not persist ClaudeHub credential; keeping it in memory")
        }
    }

    func remove(for account: Account) throws {
        values[account.id] = nil
        permissionRequired.remove(account.id)
        try persistence?.remove(account)
    }
}

extension CredentialStoreError {
    static func requiresPermission(_ error: Error) -> Bool {
        guard let error = error as? CredentialStoreError else { return false }
        switch error {
        case .permissionRequired: return true
        case .keychain(let status):
            return [errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed, errSecUserCanceled].contains(status)
        case .malformedCredential: return false
        }
    }
}

extension Notification.Name {
    static let credentialPermissionRequired = Notification.Name("ClaudeHub.credentialPermissionRequired")
}
