import Foundation

enum AnthropicClientError: LocalizedError {
    case invalidResponse
    case http(Int)
    case rateLimitResponse(endpoint: AnthropicEndpoint, retryAt: Date?)
    case rateLimited(until: Date)

    var errorDescription: String? {
        switch self {
        case .rateLimitResponse: return L10n.text(.rateLimitedGeneric)
        case .rateLimited(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return L10n.format(.rateLimitedUntil, formatter.string(from: date))
        case .invalidResponse: return L10n.text(.invalidAnthropicResponse)
        case .http(401): return L10n.text(.sessionExpired)
        case .http(let status): return L10n.format(.anthropicHTTPFailed, status)
        }
    }
}

struct AnthropicClient {
    typealias Fetch = @Sendable (OAuthCredential) async throws -> AccountSnapshot
    private let sessions: SessionCoordinator
    private let fetch: Fetch?
    private let requests: UsageRequestCoordinator
    private let transport: AnthropicTransport

    init(sessions: SessionCoordinator = SessionCoordinator(cache: CredentialCache(persistence: .keychain)),
         requests: UsageRequestCoordinator = UsageRequestCoordinator(),
         transport: AnthropicTransport = AnthropicTransport(), fetch: Fetch? = nil) {
        self.sessions = sessions
        self.fetch = fetch
        self.requests = requests
        self.transport = transport
    }

    func configure(accounts: [Account]) async {
        guard !Task.isCancelled else { return }
        await sessions.configure(accounts)
        guard !Task.isCancelled else { return }
        await requests.configure(accounts)
        guard !Task.isCancelled else { return }
        await transport.configure(accounts)
    }

    func snapshot(for account: Account) async throws -> AccountSnapshot {
        try await requests.snapshot(for: account) { try await self.fetchWithAuthentication(for: account) }
    }

    private func performFetch(_ credential: OAuthCredential, account: Account) async throws -> AccountSnapshot {
        if let fetch { return try await fetch(credential) }
        return try await transport.snapshot(for: account, credential: credential)
    }

    private func fetchWithAuthentication(for account: Account) async throws -> AccountSnapshot {
        try Task.checkCancellation()
        let credential = try await sessions.credential(for: account)
        do {
            return try await performFetch(credential, account: account)
        } catch AnthropicClientError.http(let status) where status == 401 {
            try Task.checkCancellation()
            await transport.invalidate(account.id)
            let latest: OAuthCredential
            do { latest = try await sessions.reload(account) } catch {
                try Task.checkCancellation()
                if CredentialStoreError.requiresPermission(error) { throw CredentialStoreError.permissionRequired }
                AppLogger.write("[warn] Could not reload credentials after HTTP 401")
                throw AnthropicClientError.http(401)
            }
            do { return try await performFetch(latest, account: account) } catch AnthropicClientError.http(401) {
                try Task.checkCancellation()
                let renewed: OAuthCredential
                do { renewed = try await sessions.renew(account, force: true) } catch {
                    try Task.checkCancellation()
                    if CredentialStoreError.requiresPermission(error) { throw CredentialStoreError.permissionRequired }
                    AppLogger.write("[warn] Could not renew credentials after HTTP 401")
                    throw AnthropicClientError.http(401)
                }
                try Task.checkCancellation()
                return try await performFetch(renewed, account: account)
            }
        }
    }

    func remember(_ credential: OAuthCredential, for account: Account) async {
        await requests.pause(account)
        await transport.invalidate(account.id)
        await sessions.remember(credential, for: account)
        await requests.resume(account)
    }

    func forget(_ account: Account) async throws {
        await requests.remove(account.id)
        await transport.invalidate(account.id)
        try await sessions.forget(account)
    }

    func requiresPermission(for account: Account) async -> Bool { await sessions.requiresPermission(for: account) }

    func reconnect(_ account: Account) async throws {
        await requests.pause(account)
        await transport.invalidate(account.id)
        do {
            try await sessions.reconnect(account)
            await requests.resume(account)
        } catch {
            await requests.resume(account)
            throw error
        }
    }
}
