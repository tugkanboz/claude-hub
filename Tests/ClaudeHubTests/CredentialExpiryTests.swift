import XCTest
@testable import ClaudeHub

final class CredentialExpiryTests: XCTestCase {
    func testOptionalRefreshExpiryDecodingAndWarningBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var credential = try JSONDecoder().decode(OAuthCredential.self, from: Data(
            #"{"accessToken":"test","expiresAt":100,"refreshTokenExpiresAt":1432000000,"scopes":["user:profile"]}"#.utf8
        ))
        XCTAssertEqual(credential.refreshTokenExpiresAt, 1_432_000_000)
        XCTAssertFalse(credential.needsRefreshTokenWarning(at: now))
        XCTAssertTrue(credential.needsRefreshTokenWarning(at: now.addingTimeInterval(1)))
        credential.refreshTokenExpiresAt = 999_000_000
        XCTAssertTrue(credential.needsRefreshTokenWarning(at: now))
        credential.refreshTokenExpiresAt = nil
        XCTAssertFalse(credential.needsRefreshTokenWarning(at: now))
        let legacy = try JSONDecoder().decode(OAuthCredential.self, from: Data(#"{"accessToken":"test","expiresAt":100}"#.utf8))
        XCTAssertNil(legacy.refreshTokenExpiresAt)
    }

    func testSessionMessagesExistInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(L10n.text(.sessionExpired, language: language).contains("claude auth login"))
            XCTAssertFalse(L10n.text(.refreshTokenExpiring, language: language).isEmpty)
        }
        XCTAssertFalse(AnthropicClientError.http(401).localizedDescription.contains("HTTP 401"))
    }
}
