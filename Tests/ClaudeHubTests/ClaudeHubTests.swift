import XCTest
@testable import ClaudeHub

final class ClaudeHubTests: XCTestCase {
    func testProfileServiceNameIsStable() {
        let work = CredentialStore.serviceName(for: "/Users/example/.claude-accounts/work")
        XCTAssertEqual(work, "Claude Code-credentials-ce139327")
        XCTAssertEqual(work, CredentialStore.serviceName(for: "/Users/example/.claude-accounts/work"))
        XCTAssertNotEqual(work, CredentialStore.serviceName(for: "/Users/example/.claude-accounts/personal"))
    }

    func testCredentialCacheReadsKeychainOnlyOnceUntilInvalidated() async throws {
        let counter = CredentialLoaderCounter()
        let cache = CredentialCache(loader: { account in
            counter.load(account)
        })
        let account = Account(label: "work", configDirectory: "/tmp/work")

        let first = try await cache.read(for: account)
        let second = try await cache.read(for: account)

        XCTAssertEqual(first.accessToken, second.accessToken)
        XCTAssertEqual(counter.count, 1)

        try await cache.remove(for: account)
        _ = try await cache.read(for: account)
        XCTAssertEqual(counter.count, 2)
    }

    func testUsagePayloadDecoding() throws {
        let json = #"{"five_hour":{"utilization":42.5,"resets_at":"2026-09-18T12:00:00Z"},"seven_day":{"utilization":10,"resets_at":null}}"#
        let payload = try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.fiveHour?.utilization, 42.5)
        XCTAssertEqual(payload.sevenDay?.utilization, 10)
    }
    func testSystemLanguageResolutionAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.resolve(["tr-TR"]), .tr)
        XCTAssertEqual(AppLanguage.resolve(["en-US"]), .en)
        XCTAssertEqual(AppLanguage.resolve(["fr-FR"]), .fr)
        XCTAssertEqual(AppLanguage.resolve(["es-ES"]), .es)
        XCTAssertEqual(AppLanguage.resolve(["de-DE"]), .en)
    }

    func testAllSupportedLanguagesHaveLocalizedMenuText() {
        XCTAssertEqual(L10n.text(.refreshNow, language: .tr), "Şimdi yenile")
        XCTAssertEqual(L10n.text(.refreshNow, language: .en), "Refresh Now")
        XCTAssertEqual(L10n.text(.refreshNow, language: .fr), "Actualiser maintenant")
        XCTAssertEqual(L10n.text(.refreshNow, language: .es), "Actualizar ahora")
    }
}

private final class CredentialLoaderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func load(_ account: Account) -> OAuthCredential {
        lock.lock()
        calls += 1
        let sequence = calls
        lock.unlock()
        return OAuthCredential(
            accessToken: "token-\(sequence)",
            refreshToken: "refresh",
            expiresAt: Int64.max,
            scopes: ["user:profile"]
        )
    }
}
