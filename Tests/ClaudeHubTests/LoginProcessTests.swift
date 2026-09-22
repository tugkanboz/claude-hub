import XCTest
@testable import ClaudeHub

final class LoginProcessTests: XCTestCase {
    func testDefaultProfileCannotBeRenewed() async {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        XCTAssertTrue(ClaudeLoginRefresher.isDefaultProfile(directory))
        XCTAssertTrue(ClaudeLoginRefresher.isDefaultProfile(directory + "/../.claude"))
        XCTAssertFalse(ClaudeLoginRefresher.isDefaultProfile("/tmp/isolated-claude-profile"))
        let account = Account(label: "default", configDirectory: directory)
        let credential = OAuthCredential(accessToken: "test", refreshToken: "test", expiresAt: 1, scopes: ["user:profile"])
        do {
            try await ClaudeLoginRefresher().renew(account: account, credential: credential)
            XCTFail("Must not launch the CLI for the default profile")
        } catch LoginRefreshError.defaultProfileProtected { } catch { XCTFail("Unexpected error") }
    }

    func testSuccessfulProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try LoginProcessExecution().run(process, timeout: 2)
    }

    func testFailedProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        XCTAssertThrowsError(try LoginProcessExecution().run(process, timeout: 2))
    }

    func testTimedOutProcessIsStopped() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        XCTAssertThrowsError(try LoginProcessExecution().run(process, timeout: 0.1))
        XCTAssertFalse(process.isRunning)
    }

    func testCancelledProcessDoesNotStart() {
        let execution = LoginProcessExecution()
        execution.cancel()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertThrowsError(try execution.run(process, timeout: 2)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}
