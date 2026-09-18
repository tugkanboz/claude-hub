import CryptoKit
import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case malformedCredential

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain kaydı okunamadı (\(status)). Bu profil Claude Code ile giriş yapmış mı?"
        case .malformedCredential:
            return "Claude Code kimlik kaydı beklenen biçimde değil."
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
