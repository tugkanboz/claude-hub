import Foundation

enum AnthropicClientError: LocalizedError {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Anthropic geçersiz bir yanıt döndürdü."
        case .http(let status): return "Anthropic isteği HTTP \(status) ile başarısız oldu."
        }
    }
}

struct AnthropicClient {
    private let credentials = CredentialStore()
    private let refresher = ClaudeLoginRefresher()
    private let decoder = JSONDecoder()
    private let refreshLeadTime: Int64 = 5 * 60 * 1_000

    func snapshot(for account: Account) async throws -> AccountSnapshot {
        var credential = try credentials.read(for: account)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if credential.expiresAt > 0, credential.expiresAt <= now + refreshLeadTime {
            try await refresher.renew(account: account, credential: credential)
            credential = try credentials.read(for: account)
        }

        let accessToken = credential.accessToken
        async let usageData = request(path: "/api/oauth/usage", token: accessToken)
        async let profileData = request(path: "/api/oauth/profile", token: accessToken)
        let (usageBytes, profileBytes) = try await (usageData, profileData)
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
