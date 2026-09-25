import Security
import XCTest
@testable import ClaudeHub

final class AccessRecoveryTests: XCTestCase {
    private let account = Account(label: "account1", configDirectory: "/tmp/access-recovery-tests")

    func testExpiredAndNearExpiryCredentialsRenewBeforeSaving() async throws {
        for remaining in [-60.0, 300.0] {
            let storage = RecoveryStorage(remaining: remaining)
            let cache = storage.cache()
            let sessions = SessionCoordinator(cache: cache) { _, _ in
                let pending = await cache.requiresPermission(for: self.account)
                XCTAssertTrue(pending)
                XCTAssertNil(storage.saved)
                storage.rotate()
            }
            await sessions.configure([account])
            do { _ = try await cache.read(for: account) } catch { }
            try await sessions.reconnect(account)
            XCTAssertEqual(storage.events, ["read", "renew", "read", "write"])
            XCTAssertEqual(storage.saved?.accessToken, "renewed")
            let pending = await cache.requiresPermission(for: account)
            XCTAssertFalse(pending)
            let restarted = storage.cache()
            let persisted = try await restarted.read(for: account)
            XCTAssertEqual(persisted.accessToken, "renewed")
            await sessions.configure([])
        }
    }

    func testFreshCredentialDoesNotLaunchCLI() async throws {
        let storage = RecoveryStorage(remaining: 3_600)
        let sessions = SessionCoordinator(cache: storage.cache(), automaticRenewal: false) { _, _ in XCTFail("Fresh token") }
        await sessions.configure([account])
        try await sessions.reconnect(account)
        XCTAssertEqual(storage.events, ["read", "write"])
    }

    func testFailedOrUnchangedRenewalDoesNotCommitOrClearPermission() async throws {
        for fails in [true, false] {
            let storage = RecoveryStorage(remaining: -60)
            let cache = storage.cache()
            let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in
                if fails { throw LoginRefreshError.failed }
            }
            await sessions.configure([account])
            do { _ = try await cache.read(for: account) } catch { }
            do { try await sessions.reconnect(account); XCTFail("Must fail") }
            catch LoginRefreshError.failed { }
            XCTAssertNil(storage.saved)
            let pending = await cache.requiresPermission(for: account)
            XCTAssertTrue(pending)
            do { _ = try await sessions.renew(account); XCTFail("Must stay paused") }
            catch CredentialStoreError.permissionRequired { }
        }
    }

    func testFinalReadOrWriteDenialKeepsRecoveryPending() async throws {
        for stage in ["read", "write"] {
            let storage = RecoveryStorage(remaining: -60, deniedStage: stage)
            let cache = storage.cache()
            let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in storage.rotate() }
            await sessions.configure([account])
            do { try await sessions.reconnect(account); XCTFail("Must fail") }
            catch CredentialStoreError.permissionRequired { }
            XCTAssertNil(storage.saved)
            let pending = await cache.requiresPermission(for: account)
            XCTAssertTrue(pending)
        }
    }

    func testRemovalDuringRecoveryCancelsCLIAndDoesNotRestoreCredential() async throws {
        let started = expectation(description: "CLI started")
        let storage = RecoveryStorage(remaining: -60)
        let sessions = SessionCoordinator(cache: storage.cache(), automaticRenewal: false) { _, _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
            storage.rotate()
        }
        await sessions.configure([account])
        let recovery = Task { try await sessions.reconnect(account) }
        await fulfillment(of: [started], timeout: 2)
        try await sessions.forget(account)
        do { try await recovery.value; XCTFail("Removed account") } catch is CancellationError { }
        XCTAssertNil(storage.saved)
        XCTAssertEqual(storage.events, ["read"])
    }

    func testCallerCancellationStopsRecoveryBeforeCommit() async throws {
        let started = expectation(description: "CLI started")
        let storage = RecoveryStorage(remaining: -60)
        let sessions = SessionCoordinator(cache: storage.cache(), automaticRenewal: false) { _, _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        await sessions.configure([account])
        let recovery = Task { try await sessions.reconnect(account) }
        await fulfillment(of: [started], timeout: 2)
        recovery.cancel()
        do { try await recovery.value; XCTFail("Cancelled recovery") } catch is CancellationError { }
        XCTAssertNil(storage.saved)
    }

    func testRecoveryPreservesUsageCooldownOnSuccessAndFailure() async throws {
        for fails in [true, false] {
            let storage = RecoveryStorage(remaining: -60)
            let cache = storage.cache()
            let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in
                if fails { throw LoginRefreshError.failed }
                storage.rotate()
            }
            let deadline = Date().addingTimeInterval(3_600)
            let client = AnthropicClient(sessions: sessions) { _ in
                throw AnthropicClientError.rateLimitResponse(endpoint: .usage, retryAt: deadline)
            }
            await client.configure(accounts: [account])
            await cache.remember(storage.credential, for: account)
            do { _ = try await client.snapshot(for: account); XCTFail("Expected 429") }
            catch AnthropicClientError.rateLimited(let until) { XCTAssertEqual(until, deadline) }
            do { try await client.reconnect(account); XCTAssertFalse(fails) }
            catch LoginRefreshError.failed { XCTAssertTrue(fails) }
            do { _ = try await client.snapshot(for: account); XCTFail("Expected cooldown") }
            catch AnthropicClientError.rateLimited(let until) { XCTAssertEqual(until, deadline) }
        }
    }
}

private final class RecoveryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var source: OAuthCredential
    private var stored: OAuthCredential?
    private var recorded: [String] = []
    private let deniedStage: String?

    init(remaining: TimeInterval, deniedStage: String? = nil) {
        source = OAuthCredential(accessToken: "old", refreshToken: "refresh",
            expiresAt: Int64(Date().addingTimeInterval(remaining).timeIntervalSince1970 * 1_000), scopes: ["user:profile"])
        self.deniedStage = deniedStage
    }

    var credential: OAuthCredential { lock.lock(); defer { lock.unlock() }; return source }
    var saved: OAuthCredential? { lock.lock(); defer { lock.unlock() }; return stored }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return recorded }

    func rotate() {
        lock.lock(); defer { lock.unlock() }
        recorded.append("renew")
        source = OAuthCredential(accessToken: "renewed", refreshToken: "rotated",
            expiresAt: Int64(Date().addingTimeInterval(28_800).timeIntervalSince1970 * 1_000), scopes: ["user:profile"])
    }

    func cache() -> CredentialCache {
        let persistence = CredentialPersistence(read: { _ in self.saved }, write: { _, _ in }, remove: { _ in
            self.lock.lock(); defer { self.lock.unlock() }; self.stored = nil
        }, interactiveWrite: { credential, _ in
            self.lock.lock(); defer { self.lock.unlock() }
            if self.deniedStage == "write" { throw CredentialStoreError.keychain(errSecUserCanceled) }
            self.recorded.append("write")
            self.stored = credential
        })
        return CredentialCache(loader: { _ in throw CredentialStoreError.keychain(errSecInteractionNotAllowed) },
            persistence: persistence, interactiveLoader: { _ in
                self.lock.lock(); defer { self.lock.unlock() }
                self.recorded.append("read")
                if self.deniedStage == "read", self.source.accessToken == "renewed" {
                    throw CredentialStoreError.keychain(errSecUserCanceled)
                }
                return self.source
            })
    }
}
