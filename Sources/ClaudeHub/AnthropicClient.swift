import Foundation

enum AnthropicClientError: LocalizedError {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return L10n.text(.invalidAnthropicResponse)
        case .http(401): return L10n.text(.sessionExpired)
        case .http(let status): return L10n.format(.anthropicHTTPFailed, status)
        }
    }
}

struct AnthropicClient {
    typealias Fetch = @Sendable (OAuthCredential) async throws -> AccountSnapshot
    private let sessions: SessionCoordinator
    private let fetch: Fetch

    init(sessions: SessionCoordinator = SessionCoordinator(cache: CredentialCache(persistence: .keychain)),
         fetch: @escaping Fetch = { try await Self.fetchSnapshot(credential: $0) }) {
        self.sessions = sessions
        self.fetch = fetch
    }

    func configure(accounts: [Account]) async { await sessions.configure(accounts) }

    func snapshot(for account: Account) async throws -> AccountSnapshot {
        try Task.checkCancellation()
        let credential = try await sessions.credential(for: account)
        do {
            return try await fetch(credential)
        } catch AnthropicClientError.http(let status) where status == 401 {
            try Task.checkCancellation()
            let latest: OAuthCredential
            do { latest = try await sessions.reload(account) } catch {
                try Task.checkCancellation()
                if CredentialStoreError.requiresPermission(error) { throw CredentialStoreError.permissionRequired }
                AppLogger.write("[warn] Could not reload credentials after HTTP 401")
                throw AnthropicClientError.http(401)
            }
            do { return try await fetch(latest) } catch AnthropicClientError.http(401) {
                try Task.checkCancellation()
                let renewed: OAuthCredential
                do { renewed = try await sessions.renew(account, force: true) } catch {
                    try Task.checkCancellation()
                    if CredentialStoreError.requiresPermission(error) { throw CredentialStoreError.permissionRequired }
                    AppLogger.write("[warn] Could not renew credentials after HTTP 401")
                    throw AnthropicClientError.http(401)
                }
                try Task.checkCancellation()
                return try await fetch(renewed)
            }
        }
    }

    func remember(_ credential: OAuthCredential, for account: Account) async {
        await sessions.remember(credential, for: account)
    }

    func forget(_ account: Account) async throws {
        try await sessions.forget(account)
    }

    func requiresPermission(for account: Account) async -> Bool { await sessions.requiresPermission(for: account) }

    func reconnect(_ account: Account) async throws { try await sessions.reconnect(account) }

    private static func fetchSnapshot(credential: OAuthCredential) async throws -> AccountSnapshot {
        let token = credential.accessToken
        async let usageData = request(path: "/api/oauth/usage", token: token)
        async let profileData = request(path: "/api/oauth/profile", token: token)
        let (usageBytes, profileBytes) = try await (usageData, profileData)
        let decoder = JSONDecoder()
        let usage = try decoder.decode(UsagePayload.self, from: usageBytes)
        let profile = try decoder.decode(ProfilePayload.self, from: profileBytes)
        return AccountSnapshot(
            email: profile.account.email,
            organizationID: profile.organization.uuid,
            usage: usage,
            fetchedAt: Date(),
            refreshTokenExpiresAt: credential.refreshTokenExpiresAt
        )
    }

    private static func request(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "https://api.anthropic.com\(path)") else {
            throw AnthropicClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicClientError.http(http.statusCode)
        }
        return data
    }
}
