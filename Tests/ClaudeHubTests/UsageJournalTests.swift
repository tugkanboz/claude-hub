import XCTest
@testable import ClaudeHub

final class UsageJournalTests: XCTestCase {
    private let id = UUID()
    private let reset = "2026-09-23T12:00:00Z"

    func testNextHourNeverBackfillsStartupOrWake() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(HourBoundary.next(after: date("2026-09-22T10:25:00Z"), calendar: calendar), date("2026-09-22T11:00:00Z"))
        XCTAssertEqual(HourBoundary.next(after: date("2026-09-22T11:00:00Z"), calendar: calendar), date("2026-09-22T12:00:00Z"))
        let scheduled = date("2026-09-22T11:00:00Z")
        XCTAssertTrue(HourBoundary.canRecord(scheduled: scheduled, now: scheduled.addingTimeInterval(1), calendar: calendar))
        XCTAssertFalse(HourBoundary.canRecord(scheduled: scheduled, now: scheduled.addingTimeInterval(60), calendar: calendar))
        XCTAssertFalse(HourBoundary.canRecord(scheduled: scheduled, now: scheduled.addingTimeInterval(3_600), calendar: calendar))
        XCTAssertFalse(HourBoundary.canRecord(scheduled: scheduled, now: scheduled.addingTimeInterval(-1), calendar: calendar))
    }

    func testLocalHourAlignmentWithFractionalTimezoneAndDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        let next = try XCTUnwrap(HourBoundary.next(after: date("2026-09-22T10:25:00Z"), calendar: calendar))
        XCTAssertEqual(next, date("2026-09-22T11:15:00Z"))
        XCTAssertEqual(calendar.component(.minute, from: next), 0)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let spring = try XCTUnwrap(HourBoundary.next(after: date("2026-03-08T06:30:00Z"), calendar: calendar))
        XCTAssertEqual(spring, date("2026-03-08T07:00:00Z"))
        let fall = try XCTUnwrap(HourBoundary.next(after: date("2026-11-01T05:30:00Z"), calendar: calendar))
        XCTAssertGreaterThan(fall, date("2026-11-01T05:30:00Z"))
        XCTAssertEqual(calendar.component(.minute, from: fall), 0)
    }

    func testFreshnessAndNoSensitiveFields() throws {
        let now = date("2026-09-22T11:00:00Z")
        let sample = try snapshot(24, at: now.addingTimeInterval(-300))
        let entry = make(now, sample: sample)
        XCTAssertEqual(entry.sampledAt, sample.fetchedAt)
        XCTAssertEqual(entry.status, "available")
        let encoded = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private@example.com"))
        XCTAssertFalse(encoded.contains("private-org"))
        XCTAssertFalse(encoded.contains("accessToken"))
        XCTAssertFalse(encoded.contains("configDirectory"))
        XCTAssertEqual(make(now, sample: try snapshot(24, at: now.addingTimeInterval(-361))).status, "unavailable")
        XCTAssertEqual(make(now, sample: try snapshot(24, at: now.addingTimeInterval(1))).status, "unavailable")
        XCTAssertTrue(make(now, sample: nil).windows.isEmpty)
    }

    func testIncreaseAndThresholdHaveReadableMeaning() throws {
        let firstTime = date("2026-09-22T10:00:00Z")
        let first = make(firstTime, sample: try snapshot(70, at: firstTime))
        let now = firstTime.addingTimeInterval(3_600)
        let entry = make(now, sample: try snapshot(85, at: now), previous: first, success: first)
        XCTAssertTrue(entry.summary.contains { $0.contains("+15.0 percentage points") })
        XCTAssertTrue(entry.summary.contains { $0.contains("remaining share is 15.0%") })
    }

    func testResetChangeNeverProducesCrossPeriodDelta() throws {
        let firstTime = date("2026-09-23T11:00:00Z")
        let first = make(firstTime, sample: try snapshot(95, at: firstTime))
        let now = firstTime.addingTimeInterval(3_600)
        let entry = make(now, sample: try snapshot(2, at: now, reset: "2026-09-23T17:00:00Z"), previous: first, success: first)
        XCTAssertTrue(entry.summary.contains { $0.contains("new usage period") })
        XCTAssertFalse(entry.summary.contains { $0.contains("percentage points") })
    }

    func testGapAndRecoveryDoNotInventUsage() throws {
        let firstTime = date("2026-09-22T10:00:00Z")
        let first = make(firstTime, sample: try snapshot(30, at: firstTime))
        let missing = make(firstTime.addingTimeInterval(3_600), sample: nil, previous: first, success: first)
        let now = firstTime.addingTimeInterval(13 * 3_600)
        let entry = make(now, sample: try snapshot(60, at: now), previous: missing, success: first)
        XCTAssertTrue(entry.summary.contains { $0.contains("13.0 hours") })
        XCTAssertTrue(entry.summary.contains { $0.contains("available again") })
        XCTAssertFalse(entry.summary.contains { $0.contains("percentage points") || $0.contains("computer") })
    }

    func testEquivalentResetFormatsAndDecrease() throws {
        let firstTime = date("2026-09-22T10:00:00Z")
        let first = make(firstTime, sample: try snapshot(30, at: firstTime))
        let now = firstTime.addingTimeInterval(3_600)
        let entry = make(now, sample: try snapshot(20, at: now, reset: "2026-09-23T12:00:00.000Z"), previous: first, success: first)
        XCTAssertTrue(entry.summary.contains { $0.contains("decreased") && $0.contains("not assumed") })
        XCTAssertFalse(entry.summary.contains { $0.contains("new usage period") })
    }

    func testFourLanguagesFormatRealNumbers() throws {
        let now = date("2026-09-22T11:00:00Z")
        for language in AppLanguage.allCases {
            let entry = UsageJournalSummary.entry(accountID: id, scheduled: now, now: now, snapshot: try snapshot(85, at: now),
                previous: nil, previousSuccess: nil, language: language)
            XCTAssertEqual(entry.language, language.rawValue)
            XCTAssertTrue(entry.summary.contains { $0.contains("85") && $0.contains("%") })
            XCTAssertFalse(entry.summary.contains { $0.contains("%@") || $0.contains("%.1f") })
        }
    }

    func testPersistenceRestartDeduplicationAndReadableLog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-09-22T10:00:00Z")
        let store = UsageJournalStore(directory: root)
        try await store.record(accountID: id, scheduled: now, now: now, snapshot: snapshot(20, at: now), language: .en)
        let restarted = UsageJournalStore(directory: root)
        try await restarted.record(accountID: id, scheduled: now, now: now, snapshot: snapshot(20, at: now), language: .en)
        let next = now.addingTimeInterval(3_600)
        try await restarted.record(accountID: id, scheduled: next, now: next, snapshot: snapshot(35, at: next), language: .en)
        let directory = root.appendingPathComponent(id.uuidString)
        let entries = try read(directory.appendingPathComponent("2026-09-22.json"))
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[1].summary.contains { $0.contains("+15.0 percentage points") })
        let text = try String(contentsOf: directory.appendingPathComponent("2026-09-22.log"))
        XCTAssertTrue(text.contains("Usage increased"))
        XCTAssertFalse(text.contains("private@example.com"))
    }

    func testCorruptDailyFileIsNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("2026-09-22.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: file)
        let now = date("2026-09-22T10:00:00Z")
        do {
            try await UsageJournalStore(directory: root).record(accountID: id, scheduled: now, now: now, snapshot: nil, language: .en)
            XCTFail("Must not replace corrupt history")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testRetentionOnlyDeletesOldJournalFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("2026-08-22.log")
        let keep = directory.appendingPathComponent("2026-08-24.log")
        let unrelated = directory.appendingPathComponent("notes.txt")
        for file in [old, keep, unrelated] { try Data("keep".utf8).write(to: file) }
        let now = date("2026-09-22T10:00:00Z")
        try await UsageJournalStore(directory: root).record(accountID: id, scheduled: now, now: now, snapshot: nil, language: .en)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func make(_ now: Date, sample: AccountSnapshot?, previous: UsageJournalEntry? = nil, success: UsageJournalEntry? = nil) -> UsageJournalEntry {
        UsageJournalSummary.entry(accountID: id, scheduled: now, now: now, snapshot: sample, previous: previous, previousSuccess: success, language: .en)
    }

    private func snapshot(_ percent: Double, at: Date, reset: String? = nil) throws -> AccountSnapshot {
        let json = "{\"five_hour\":{\"utilization\":\(percent),\"resets_at\":\"\(reset ?? self.reset)\"}}"
        return AccountSnapshot(email: "private@example.com", organizationID: "private-org", usage: try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8)), fetchedAt: at)
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func read(_ file: URL) throws -> [UsageJournalEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([UsageJournalEntry].self, from: Data(contentsOf: file))
    }
}
