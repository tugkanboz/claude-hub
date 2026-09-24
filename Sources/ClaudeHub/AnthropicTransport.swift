import Foundation

enum AnthropicEndpoint: String, Sendable {
    case usage = "/api/oauth/usage"
    case profile = "/api/oauth/profile"
}

actor AnthropicTransport {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let send: Send
    private let now: @Sendable () -> Date
    private var profiles: [UUID: (payload: ProfilePayload, fetchedAt: Date)] = [:]
    private var generations: [UUID: UUID] = [:]

    init(send: @escaping Send = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.send = send
        self.now = now
    }

    func configure(_ accounts: [Account]) {
        let remaining = Set(accounts.map(\.id))
        for id in generations.keys where !remaining.contains(id) { invalidate(id) }
    }

    func invalidate(_ id: UUID) {
        profiles[id] = nil
        generations[id] = nil
    }

    func snapshot(for account: Account, credential: OAuthCredential) async throws -> AccountSnapshot {
        let generation = generations[account.id] ?? UUID()
        generations[account.id] = generation
        let usageData = try await request(.usage, token: credential.accessToken)
        try Task.checkCancellation()
        guard generations[account.id] == generation else { throw CancellationError() }
        let measuredAt = now()
        let usage = try JSONDecoder().decode(UsagePayload.self, from: usageData)
        let profile: ProfilePayload
        if let cached = profiles[account.id], now().timeIntervalSince(cached.fetchedAt) >= 0,
           now().timeIntervalSince(cached.fetchedAt) < 21_600 {
            profile = cached.payload
        } else {
            let profileData = try await request(.profile, token: credential.accessToken)
            profile = try JSONDecoder().decode(ProfilePayload.self, from: profileData)
            try Task.checkCancellation()
            guard generations[account.id] == generation else { throw CancellationError() }
            profiles[account.id] = (profile, now())
        }
        try Task.checkCancellation()
        guard generations[account.id] == generation else { throw CancellationError() }
        return AccountSnapshot(email: profile.account.email, organizationID: profile.organization.uuid,
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
