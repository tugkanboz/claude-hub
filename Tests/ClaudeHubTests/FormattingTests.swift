import XCTest
@testable import ClaudeHub

final class FormattingTests: XCTestCase {
    func testUsageLineWithMissingAndInvalidReset() {
        for reset in [nil, "invalid"] as [String?] {
            XCTAssertEqual(UsageFormatting.line(name: "5 hours", window: UsageWindow(utilization: 12.5, resetsAt: reset), language: .en), "5 hours: 12.5% used")
        }
    }

    func testResetDatesAndBoundaries() {
        let now = Date(timeIntervalSince1970: 0)
        for (reset, expected) in [
            ("1970-01-02T02:00:00Z", "1d 2h"),
            ("1970-01-01T02:00:00.000Z", "2h"),
            ("1970-01-01T00:05:00Z", "5min"),
            ("1969-12-31T23:00:00Z", "1min"),
        ] {
            let result = UsageFormatting.line(name: "Usage", window: UsageWindow(utilization: 25, resetsAt: reset), now: now, language: .en)
            XCTAssertEqual(result, "Usage: 25.0% · resets in \(expected)")
        }
    }

    func testExtraUsagePreservesFractionalCredits() {
        XCTAssertNil(UsageFormatting.extraUsage(ExtraUsage(isEnabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil), language: .en))
        XCTAssertEqual(UsageFormatting.extraUsage(ExtraUsage(isEnabled: true, monthlyLimit: 1000, usedCredits: 123.5, utilization: nil), language: .en), "Extra usage: $1.24 / $10.00")
        XCTAssertEqual(UsageFormatting.extraUsage(ExtraUsage(isEnabled: true, monthlyLimit: nil, usedCredits: nil, utilization: nil), language: .en), "Extra usage: $0.00")
    }

    func testLogRotationPreservesLatestBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("menubar.log")
        try Data("old".utf8).write(to: file)
        try AppLogger.rotateIfNeeded(file: file, maximumBytes: 3)
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("1")), "old")
        try Data("new".utf8).write(to: file)
        try AppLogger.rotateIfNeeded(file: file, maximumBytes: 3)
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("1")), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
