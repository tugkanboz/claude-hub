import XCTest
@testable import ClaudeHub

final class LastUsageStoreTests: XCTestCase {
    private let account = Account(label: "account1", configDirectory: "/tmp/last-usage-test")

    func testLastUsageSurvivesRestartWithoutPersonalData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let usage = try JSONDecoder().decode(UsagePayload.self, from: Data("{\"five_hour\":{\"utilization\":0.25}}".utf8))
        let snapshot = AccountSnapshot(email: "private@example.com", organizationID: "secret-org",
                                       usage: usage, fetchedAt: now, refreshTokenExpiresAt: 1_000)
        try LastUsageStore(directory: directory).save(snapshot, for: account)

        let file = directory.appendingPathComponent(account.id.uuidString + ".json")
        let stored = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(stored.contains("private@example.com"))
        XCTAssertFalse(stored.contains("secret-org"))
        XCTAssertFalse(stored.contains("refreshToken"))
        let restored = try LastUsageStore(directory: directory).load(for: account, now: now.addingTimeInterval(3600))
        XCTAssertEqual(restored?.fetchedAt, now)
        XCTAssertEqual(restored?.usage.fiveHour?.utilization, 0.25)
        XCTAssertNil(restored?.email)
        XCTAssertNil(restored?.refreshTokenExpiresAt)
        try LastUsageStore(directory: directory).remove(for: account)
        XCTAssertNil(try LastUsageStore(directory: directory).load(for: account))
    }

    func testOldOrWrongAccountDataIsIgnoredAndCorruptFileFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LastUsageStore(directory: directory)
        let other = Account(label: "other", configDirectory: "/tmp/other")
        let usage = try JSONDecoder().decode(UsagePayload.self, from: Data("{}".utf8))
        let old = AccountSnapshot(email: nil, organizationID: nil, usage: usage,
                                  fetchedAt: Date().addingTimeInterval(-8 * 86_400))
        try store.save(old, for: account)
        XCTAssertNil(try store.load(for: account))

        let wrong = AccountSnapshot(email: nil, organizationID: nil, usage: usage, fetchedAt: Date())
        try store.save(wrong, for: other)
        let source = directory.appendingPathComponent(other.id.uuidString + ".json")
        let destination = directory.appendingPathComponent(account.id.uuidString + ".json")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        XCTAssertNil(try store.load(for: account))
        try Data("corrupt".utf8).write(to: destination)
        XCTAssertThrowsError(try store.load(for: account))
    }

    func testSymlinkIsRejectedBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let usage = try JSONDecoder().decode(UsagePayload.self, from: Data("{}".utf8))
        let snapshot = AccountSnapshot(email: nil, organizationID: nil, usage: usage, fetchedAt: Date())
        XCTAssertThrowsError(try LastUsageStore(directory: link).save(snapshot, for: account))
        XCTAssertThrowsError(try LastUsageStore(directory: link).load(for: account))
    }
}
