import Security
import XCTest
@testable import ClaudeHub

final class KeychainPermissionTests: XCTestCase {
    private let account = Account(label: "account1", configDirectory: "/tmp/claudehub-permission-tests")
    private let credential = OAuthCredential(accessToken: "cached", refreshToken: "refresh", expiresAt: Int64.max, scopes: ["user:profile"])

    func testBackgroundDenialIsLatchedAcrossRepeatedPolls() async throws {
        let calls = PermissionCalls()
        let cache = CredentialCache(loader: { _ in
            calls.record()
            throw CredentialStoreError.keychain(errSecInteractionNotAllowed)
        })
        for _ in 0..<6 {
            do { _ = try await cache.read(for: account); XCTFail("Expected permission state") }
            catch CredentialStoreError.permissionRequired { }
        }
        XCTAssertEqual(calls.count, 1)
        let required = await cache.requiresPermission(for: account)
        XCTAssertTrue(required)
    }

    func testLockedOwnRecordDoesNotFallBackToSource() async throws {
        let calls = PermissionCalls()
        let persistence = CredentialPersistence(read: { _ in
            calls.record()
            throw CredentialStoreError.keychain(errSecInteractionNotAllowed)
        }, write: { _, _ in XCTFail("Must not write") }, remove: { _ in })
        let cache = CredentialCache(loader: { _ in
            XCTFail("Must not read source")
            throw CredentialStoreError.malformedCredential
        }, persistence: persistence)
        for _ in 0..<3 {
            do { _ = try await cache.read(for: account); XCTFail("Expected permission state") }
            catch CredentialStoreError.permissionRequired { }
        }
        XCTAssertEqual(calls.count, 1)
    }

    func testValidCachedTokenKeepsWorkingWhileRenewalIsPaused() async throws {
        let cache = CredentialCache(loader: { _ in throw CredentialStoreError.keychain(errSecInteractionNotAllowed) })
        await cache.remember(credential, for: account)
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in XCTFail("Must not launch CLI") }
        let client = AnthropicClient(sessions: sessions) { _ in try Self.snapshot() }
        await client.configure(accounts: [account])
        for _ in 0..<3 {
            do { _ = try await sessions.renew(account); XCTFail("Expected permission state") }
            catch CredentialStoreError.permissionRequired { }
            _ = try await client.snapshot(for: account)
        }
    }

    func testPostRenewalDenialStopsFurtherCLIAnd401ReloadAttempts() async throws {
        let reads = PermissionCalls()
        let renewals = PermissionCalls()
        let cache = CredentialCache(loader: { _ in
            reads.record()
            throw CredentialStoreError.keychain(errSecInteractionNotAllowed)
        })
        await cache.remember(credential, for: account)
        let sessions = SessionCoordinator(cache: cache, automaticRenewal: false) { _, _ in renewals.record() }
        let client = AnthropicClient(sessions: sessions) { _ in throw AnthropicClientError.http(401) }
        await client.configure(accounts: [account])
        do { _ = try await sessions.renew(account, force: true); XCTFail("Expected import denial") }
        catch CredentialStoreError.permissionRequired { }
        for _ in 0..<3 {
            do { _ = try await client.snapshot(for: account); XCTFail("Expected permission state") }
            catch CredentialStoreError.permissionRequired { }
        }
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(renewals.count, 1)
    }

    func testManualAuthorizationUnblocksOnlySelectedAccount() async throws {
        let manual = PermissionCalls()
        let writes = PermissionCalls()
        let token = credential
        let persistence = CredentialPersistence(read: { _ in nil }, write: { _, _ in }, remove: { _ in },
            interactiveWrite: { _, _ in writes.record() })
        let cache = CredentialCache(loader: { _ in throw CredentialStoreError.keychain(errSecInteractionNotAllowed) },
            persistence: persistence, interactiveLoader: { _ in manual.record(); return token })
        let other = Account(label: "account2", configDirectory: "/tmp/claudehub-other")
        for item in [account, other] {
            do { _ = try await cache.read(for: item); XCTFail("Expected permission state") }
            catch CredentialStoreError.permissionRequired { }
        }
        try await cache.authorize(for: account)
        let selected = try await cache.read(for: account)
        let stillBlocked = await cache.requiresPermission(for: other)
        let selectedBlocked = await cache.requiresPermission(for: account)
        XCTAssertEqual(selected.accessToken, token.accessToken)
        XCTAssertFalse(selectedBlocked)
        XCTAssertTrue(stillBlocked)
        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(writes.count, 1)
    }

    func testCancelDoesNotClearPermissionStateOrRetryAutomatically() async throws {
        let calls = PermissionCalls()
        let cache = CredentialCache(loader: { _ in
            calls.record()
            throw CredentialStoreError.keychain(errSecInteractionNotAllowed)
        }, interactiveLoader: { _ in throw CredentialStoreError.keychain(errSecUserCanceled) })
        do { _ = try await cache.read(for: account) } catch { }
        do { try await cache.authorize(for: account); XCTFail("Expected cancellation") }
        catch CredentialStoreError.permissionRequired { }
        do { _ = try await cache.read(for: account); XCTFail("Must stay paused") }
        catch CredentialStoreError.permissionRequired { }
        XCTAssertEqual(calls.count, 1)
    }

    func testOwnWriteDenialRetainsMemoryAndDoesNotKeepWriting() async throws {
        let writes = PermissionCalls()
        let persistence = CredentialPersistence(read: { _ in nil }, write: { _, _ in
            writes.record()
            throw CredentialStoreError.keychain(errSecInteractionNotAllowed)
        }, remove: { _ in })
        let cache = CredentialCache(persistence: persistence)
        await cache.remember(credential, for: account)
        await cache.remember(credential, for: account)
        let current = try await cache.read(for: account)
        XCTAssertEqual(current.accessToken, credential.accessToken)
        XCTAssertEqual(writes.count, 1)
    }

    func testLegacyInteractionScopeRestoresSettingAfterFailure() {
        var before: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&before), errSecSuccess)
        let status = KeychainAccess.perform(.background) {
            var allowed: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertFalse(allowed.boolValue)
            return errSecInteractionNotAllowed
        }
        XCTAssertEqual(status, errSecInteractionNotAllowed)
        var after: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&after), errSecSuccess)
        XCTAssertEqual(after.boolValue, before.boolValue)
        XCTAssertEqual(KeychainAccess.perform(.userInitiated) {
            var allowed: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertTrue(allowed.boolValue)
            return errSecSuccess
        }, errSecSuccess)
    }

    private static func snapshot() throws -> AccountSnapshot {
        AccountSnapshot(email: nil, organizationID: nil,
            usage: try JSONDecoder().decode(UsagePayload.self, from: Data("{}".utf8)), fetchedAt: Date())
    }
}

private final class PermissionCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); defer { lock.unlock() }; value += 1 }
}
