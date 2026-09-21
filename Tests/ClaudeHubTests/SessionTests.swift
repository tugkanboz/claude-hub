import XCTest
@testable import ClaudeHub

final class SessionTests: XCTestCase {
    private let account = Account(label: "account1", configDirectory: "/tmp/claudehub-test-account1")

    func testPersistentCacheSurvivesRestartWithoutSourceRead() async throws {
        let storage = FakeCredentials()
        let first = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        _ = try await first.read(for: account)
        let restarted = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        _ = try await restarted.read(for: account)
        XCTAssertEqual(storage.readCount, 1)
        try await restarted.remove(for: account)
        let readded = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        _ = try await readded.read(for: account)
        XCTAssertEqual(storage.readCount, 2)
    }

    func testReloadReplacesPersistentCredential() async throws {
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        _ = try await cache.read(for: account)
        storage.setToken("new")
        _ = try await cache.reload(for: account)
        let restarted = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        let credential = try await restarted.read(for: account)
        XCTAssertEqual(credential.accessToken, "new")
        XCTAssertEqual(storage.readCount, 2)
    }

    func test401ReloadThenRenewThenRetry() async throws {
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() })
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in storage.setToken("new") }
        let attempts = RequestRecorder()
        let client = AnthropicClient(sessions: sessions) { credential in
            await attempts.record(credential.accessToken)
            guard credential.accessToken == "new" else { throw AnthropicClientError.http(401) }
            return try Self.snapshot()
        }
        await client.configure(accounts: [account])
        _ = try await client.snapshot(for: account)
        let tokens = await attempts.tokens
        XCTAssertEqual(tokens, ["old", "old", "new"])
        XCTAssertEqual(storage.readCount, 3)
    }

    func testExternalLoginRecoversWithoutRenewal() async throws {
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() })
        _ = try await cache.read(for: account)
        storage.setToken("new")
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in XCTFail("Must not renew") }
        let client = AnthropicClient(sessions: sessions) { credential in
            guard credential.accessToken == "new" else { throw AnthropicClientError.http(401) }
            return try Self.snapshot()
        }
        await client.configure(accounts: [account])
        _ = try await client.snapshot(for: account)
        XCTAssertEqual(storage.readCount, 2)
    }

    func testFailedRenewalDoesNotPreventValidUsage() async throws {
        let storage = FakeCredentials()
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in storage.loadSource() }), automaticRenewal: false) { _, _ in
            throw LoginRefreshError.failed
        }
        let client = AnthropicClient(sessions: sessions) { _ in try Self.snapshot() }
        await client.configure(accounts: [account])
        do { _ = try await sessions.renew(account, force: true); XCTFail("Expected failure") } catch { }
        _ = try await client.snapshot(for: account)
    }

    func testRepeated401IsBounded() async throws {
        let storage = FakeCredentials()
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in storage.loadSource() }), automaticRenewal: false) { _, _ in }
        let attempts = RequestRecorder()
        let client = AnthropicClient(sessions: sessions) { credential in
            await attempts.record(credential.accessToken)
            throw AnthropicClientError.http(401)
        }
        await client.configure(accounts: [account])
        do { _ = try await client.snapshot(for: account); XCTFail("Expected 401") } catch AnthropicClientError.http(401) { }
        let tokens = await attempts.tokens
        XCTAssertEqual(tokens.count, 3)
    }

    func testNonAuthenticationFailureDoesNotReloadOrRenew() async throws {
        let storage = FakeCredentials()
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in storage.loadSource() }), automaticRenewal: false) { _, _ in XCTFail("Must not renew") }
        let client = AnthropicClient(sessions: sessions) { _ in throw AnthropicClientError.http(429) }
        await client.configure(accounts: [account])
        do { _ = try await client.snapshot(for: account); XCTFail("Expected 429") } catch AnthropicClientError.http(429) { }
        XCTAssertEqual(storage.readCount, 1)
    }

    func testConcurrentRenewalsShareOneOperation() async throws {
        let storage = FakeCredentials()
        let calls = RequestRecorder()
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in storage.loadSource() }), automaticRenewal: false) { _, _ in
            await calls.record("renew")
            try await Task.sleep(nanoseconds: 100_000_000)
            storage.setToken("new")
        }
        await sessions.configure([account])
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await sessions.renew(self.account, force: true).accessToken } }
            for try await token in group { XCTAssertEqual(token, "new") }
        }
        let recorded = await calls.tokens
        XCTAssertEqual(recorded.count, 1)
    }

    func testRenewalRunsWithoutUsagePolling() async throws {
        let renewed = expectation(description: "Independent renewal")
        let credential = OAuthCredential(accessToken: "test", refreshToken: "test", expiresAt: 1, scopes: ["user:profile"])
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in credential })) { _, _ in renewed.fulfill() }
        await sessions.configure([account])
        _ = try await sessions.credential(for: account)
        await fulfillment(of: [renewed], timeout: 2)
        await sessions.configure([])
    }

    func testRenewalPolicyUsesExpiryAndBackoff() {
        let now = Date(timeIntervalSince1970: 1_000)
        let credential = OAuthCredential(accessToken: "test", refreshToken: "test", expiresAt: 2_000_000, scopes: [])
        XCTAssertEqual(RenewalPolicy.scheduledDate(for: credential, now: now).timeIntervalSince1970, 1_400)
        XCTAssertEqual(RenewalPolicy.scheduledDate(for: credential, now: Date(timeIntervalSince1970: 3_000)).timeIntervalSince1970, 3_000)
        XCTAssertEqual(RenewalPolicy.retryDelay(failures: 1), 300)
        XCTAssertEqual(RenewalPolicy.retryDelay(failures: 10), 1_800)
    }

    func testFreshExternalCredentialSkipsScheduledCLIRenewal() async throws {
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() })
        _ = try await cache.read(for: account)
        storage.setToken("external")
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in XCTFail("Already renewed externally") }
        await sessions.configure([account])
        let credential = try await sessions.renew(account)
        XCTAssertEqual(credential.accessToken, "external")
    }

    func testDeniedReloadDoesNotLoopOrRenew() async throws {
        let cache = CredentialCache(loader: { _ in throw CredentialStoreError.keychain(-25293) })
        await cache.remember(OAuthCredential(accessToken: "test", refreshToken: "test", expiresAt: 1, scopes: []), for: account)
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in XCTFail("Permission denied") }
        let attempts = RequestRecorder()
        let client = AnthropicClient(sessions: sessions) { credential in
            await attempts.record(credential.accessToken)
            throw AnthropicClientError.http(401)
        }
        await client.configure(accounts: [account])
        do { _ = try await client.snapshot(for: account); XCTFail("Expected failure") } catch AnthropicClientError.http(401) { }
        let recorded = await attempts.tokens
        XCTAssertEqual(recorded.count, 1)
    }

    func testRemovalDuringRenewalDoesNotRestoreCache() async throws {
        let entered = expectation(description: "Renewal started")
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() }, persistence: storage.persistence)
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in
            entered.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        await sessions.configure([account])
        let task = Task { try await sessions.renew(account, force: true) }
        await fulfillment(of: [entered], timeout: 2)
        try await sessions.forget(account)
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertNil(try storage.persistence.read(account))
        do { _ = try await sessions.credential(for: account); XCTFail("Removed account") } catch is CancellationError { }
    }

    func testPersistenceWriteFailureKeepsUsableMemoryCredential() async throws {
        let storage = FakeCredentials()
        let persistence = CredentialPersistence(read: { _ in nil }, write: { _, _ in throw CredentialStoreError.keychain(-25293) }, remove: { _ in })
        let cache = CredentialCache(loader: { _ in storage.loadSource() }, persistence: persistence)
        let first = try await cache.read(for: account)
        let second = try await cache.read(for: account)
        XCTAssertEqual(first.accessToken, second.accessToken)
        XCTAssertEqual(storage.readCount, 1)
    }

    func testManualReconnectReplacesCachedTokenWithoutRestart() async throws {
        let storage = FakeCredentials()
        let cache = CredentialCache(loader: { _ in storage.loadSource() })
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false)
        await sessions.configure([account])
        _ = try await sessions.credential(for: account)
        storage.setToken("manual-login")
        try await sessions.reconnect(account)
        let latest = try await sessions.credential(for: account)
        XCTAssertEqual(latest.accessToken, "manual-login")
    }

    private static func snapshot() throws -> AccountSnapshot {
        AccountSnapshot(email: nil, organizationID: nil, usage: try JSONDecoder().decode(UsagePayload.self, from: Data("{}".utf8)), fetchedAt: Date())
    }
}

private actor RequestRecorder {
    var tokens: [String] = []
    func record(_ value: String) { tokens.append(value) }
}

private final class FakeCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var token = "old"
    private var reads = 0
    private var stored: [UUID: OAuthCredential] = [:]

    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func setToken(_ value: String) { lock.lock(); defer { lock.unlock() }; token = value }
    func loadSource() -> OAuthCredential {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        return OAuthCredential(accessToken: token, refreshToken: "test", expiresAt: Int64.max, scopes: ["user:profile"])
    }
    var persistence: CredentialPersistence {
        CredentialPersistence(read: { account in
            self.lock.lock(); defer { self.lock.unlock() }; return self.stored[account.id]
        }, write: { credential, account in
            self.lock.lock(); defer { self.lock.unlock() }; self.stored[account.id] = credential
        }, remove: { account in
            self.lock.lock(); defer { self.lock.unlock() }; self.stored[account.id] = nil
        })
    }
}
