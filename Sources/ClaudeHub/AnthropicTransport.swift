import Foundation

enum AnthropicEndpoint: String, Sendable {
    case usage = "/api/oauth/usage"
    case profile = "/api/oauth/profile"
}

actor AnthropicTransport {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let send: Send
    private let now: @Sendable () -> Date
    private let profileCooldownStore: RateLimitStore?
    private var profiles: [UUID: (payload: ProfilePayload, fetchedAt: Date)] = [:]
    private var profileRetryDates: [UUID: Date] = [:]
    private var active: Set<UUID> = []
    private var generations: [UUID: UUID] = [:]

    init(send: @escaping Send = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() },
         profileCooldownStore: RateLimitStore? = nil) {
        self.send = send
        self.now = now
        self.profileCooldownStore = profileCooldownStore
    }

    func configure(_ accounts: [Account]) {
        let remaining = Set(accounts.map(\.id))
        for id in active.subtracting(remaining) { remove(id) }
        for id in remaining.subtracting(active) {
            do { profileRetryDates[id] = try profileCooldownStore?.load(for: id, now: now()) }
            catch { AppLogger.write("[warn] Could not load profile cooldown account=\(id)") }
        }
        active = remaining
    }

    func invalidate(_ id: UUID) {
        profiles[id] = nil
        generations[id] = nil
    }

    func remove(_ id: UUID) {
        invalidate(id)
        active.remove(id)
        profileRetryDates[id] = nil
        do { try profileCooldownStore?.remove(for: id) }
        catch { AppLogger.write("[warn] Could not remove profile cooldown account=\(id)") }
    }

    func snapshot(for account: Account, credential: OAuthCredential) async throws -> AccountSnapshot {
        let generation = generations[account.id] ?? UUID()
        generations[account.id] = generation
        let usageData = try await request(.usage, token: credential.accessToken)
        try Task.checkCancellation()
        guard generations[account.id] == generation else { throw CancellationError() }
        let measuredAt = now()
        let usage = try JSONDecoder().decode(UsagePayload.self, from: usageData)
        let profile: ProfilePayload?
        if let cached = profiles[account.id], now().timeIntervalSince(cached.fetchedAt) >= 0,
           now().timeIntervalSince(cached.fetchedAt) < 21_600 {
            profile = cached.payload
        } else if let retry = profileRetryDates[account.id], retry > now() {
            profile = nil
        } else {
            do {
                let profileData = try await request(.profile, token: credential.accessToken)
                let fetched = try JSONDecoder().decode(ProfilePayload.self, from: profileData)
                try Task.checkCancellation()
                guard generations[account.id] == generation else { throw CancellationError() }
                profiles[account.id] = (fetched, now())
                profileRetryDates[account.id] = nil
                do { try profileCooldownStore?.remove(for: account.id) }
                catch { AppLogger.write("[warn] Could not clear profile cooldown account=\(account.id)") }
                profile = fetched
            } catch AnthropicClientError.rateLimitResponse(.profile, let suggested) {
                try Task.checkCancellation()
                guard generations[account.id] == generation else { throw CancellationError() }
                let retry = max(now().addingTimeInterval(1), suggested ?? now().addingTimeInterval(60))
                profileRetryDates[account.id] = retry
                do { try profileCooldownStore?.save(retry, for: account.id) }
                catch { AppLogger.write("[warn] Could not save profile cooldown account=\(account.id)") }
                AppLogger.write("[warn] HTTP 429 account=\(account.id) endpoint=/api/oauth/profile retryAt=\(ISO8601DateFormatter().string(from: retry))")
                profile = nil
            }
        }
        try Task.checkCancellation()
        guard generations[account.id] == generation else { throw CancellationError() }
        return AccountSnapshot(email: profile?.account.email, organizationID: profile?.organization.uuid,
            usage: usage, fetchedAt: measuredAt, refreshTokenExpiresAt: credential.refreshTokenExpiresAt)
    }

    private func request(_ endpoint: AnthropicEndpoint, token: String) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: "https://api.anthropic.com\(endpoint.rawValue)") else {
            throw AnthropicClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicClientError.invalidResponse }
        if http.statusCode == 429 {
            throw AnthropicClientError.rateLimitResponse(endpoint: endpoint,
                retryAt: RateLimitPolicy.retryDate(header: http.value(forHTTPHeaderField: "Retry-After"), now: now()))
        }
        guard (200..<300).contains(http.statusCode) else { throw AnthropicClientError.http(http.statusCode) }
        return data
    }
}
