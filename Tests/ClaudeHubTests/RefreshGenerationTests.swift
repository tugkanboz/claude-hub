import XCTest
@testable import ClaudeHub

final class RefreshGenerationTests: XCTestCase {
    func testNewRefreshRejectsPreviousResults() {
        var generation = RefreshGeneration()
        let previous = generation.advance()
        XCTAssertTrue(generation.accepts(previous))
        let current = generation.advance()
        XCTAssertFalse(generation.accepts(previous))
        XCTAssertTrue(generation.accepts(current))
    }
}
