import Foundation

enum AnthropicClientError: LocalizedError {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return L10n.text(.invalidAnthropicResponse)
        case .http(let status): return L10n.format(.anthropicHTTPFailed, status)
        }
    }
}

struct AnthropicClient {
    private let credentials = CredentialCache()
    private let refresher = ClaudeLoginRefresher()
    private let refreshLeadTime: Int64 = 5 * 60 * 1_000

    func snapshot(for account: Account) async throws -> AccountSnapshot {
        var credential = try await credentials.read(for: account)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)

        if credential.expiresAt > 0, credential.expiresAt <= now + refreshLeadTime {
            try await refresher.renew(account: account, credential: credential)
            credential = try await credentials.reload(for: account)
        }

        do {
            return try await fetchSnapshot(token: credential.accessToken)
        } catch AnthropicClientError.http(let status) where status == 401 {
            // Claude Code may have renewed the profile outside ClaudeHub.
            // Re-read only after an actual authentication failure, never on
            // the normal five-minute usage refresh.
            let latest = try await credentials.reload(for: account)
            return try await fetchSnapshot(token: latest.accessToken)
        }
    }

    func remember(_ credential: OAuthCredential, for account: Account) async {
        await credentials.remember(credential, for: account)
    }

    func forget(_ account: Account) async {
        await credentials.remove(for: account)
    }

    private func fetchSnapshot(token: String) async throws -> AccountSnapshot {
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
            fetchedAt: Date()
        )
    }

    private func request(path: String, token: String) async throws -> Data {
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
