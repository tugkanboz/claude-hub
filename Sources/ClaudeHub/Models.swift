import Foundation

struct Account: Codable, Hashable, Identifiable {
    let id: UUID
    var label: String
    var configDirectory: String

    init(id: UUID = UUID(), label: String, configDirectory: String) {
        self.id = id
        self.label = label
        self.configDirectory = configDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, configDirectory
        case legacyConfigDirectory = "config_dir"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? L10n.text(.defaultAccountLabel)
        if let current = try values.decodeIfPresent(String.self, forKey: .configDirectory) {
            configDirectory = current
        } else {
            configDirectory = try values.decode(String.self, forKey: .legacyConfigDirectory)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(label, forKey: .label)
        try values.encode(configDirectory, forKey: .configDirectory)
    }
}

struct OAuthEnvelope: Decodable {
    let claudeAiOauth: OAuthCredential
}

struct OAuthCredential: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64
    let scopes: [String]?
    var refreshTokenExpiresAt: Int64? = nil
    var subscriptionType: String? = nil
    var rateLimitTier: String? = nil

    func needsRefreshTokenWarning(at date: Date = Date()) -> Bool {
        guard let refreshTokenExpiresAt, refreshTokenExpiresAt > 0 else { return false }
        return Double(refreshTokenExpiresAt) / 1_000 - date.timeIntervalSince1970 < 5 * 86_400
    }
}

struct UsageWindow: Decodable, Equatable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Decodable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Int?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

struct UsagePayload: Decodable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDayOAuthApps: UsageWindow?
    let sevenDayCowork: UsageWindow?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct ProfilePayload: Decodable {
    struct ProfileAccount: Decodable { let email: String? }
    struct Organization: Decodable { let uuid: String? }

    let account: ProfileAccount
    let organization: Organization
}

struct AccountSnapshot {
    let email: String?
    let organizationID: String?
    let usage: UsagePayload
    let fetchedAt: Date
    var refreshTokenExpiresAt: Int64? = nil
}

enum AccountState {
    case loading
    case loaded(AccountSnapshot)
    case failed(String)
}
