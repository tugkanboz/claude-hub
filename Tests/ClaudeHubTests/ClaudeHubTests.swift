import XCTest
@testable import ClaudeHub

final class ClaudeHubTests: XCTestCase {
    func testProfileServiceNameIsStable() {
        let work = CredentialStore.serviceName(for: "/Users/example/.claude-accounts/work")
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

        await cache.remove(for: account)
        _ = try await cache.read(for: account)
        XCTAssertEqual(counter.count, 2)
    }

    func testUsagePayloadDecoding() throws {
        let json = #"{"five_hour":{"utilization":42.5,"resets_at":"2026-09-18T12:00:00Z"},"seven_day":{"utilization":10,"resets_at":null}}"#
        let payload = try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.fiveHour?.utilization, 42.5)
        XCTAssertEqual(payload.sevenDay?.utilization, 10)
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
