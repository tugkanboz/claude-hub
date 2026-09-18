import XCTest
@testable import ClaudeHub

final class ClaudeHubTests: XCTestCase {
    func testProfileServiceNameIsStable() {
        let work = CredentialStore.serviceName(for: "/Users/example/.claude-accounts/work")
        XCTAssertEqual(work, CredentialStore.serviceName(for: "/Users/example/.claude-accounts/work"))
        XCTAssertNotEqual(work, CredentialStore.serviceName(for: "/Users/example/.claude-accounts/personal"))
    }

    func testUsagePayloadDecoding() throws {
        let json = #"{"five_hour":{"utilization":42.5,"resets_at":"2026-09-18T12:00:00Z"},"seven_day":{"utilization":10,"resets_at":null}}"#
        let payload = try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.fiveHour?.utilization, 42.5)
        XCTAssertEqual(payload.sevenDay?.utilization, 10)
    }
}
