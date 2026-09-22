import XCTest
@testable import ClaudeHub

final class AccountStoreTests: XCTestCase {
    func testLegacyMigrationPersistsIdentityAndModernKeys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("accounts.json")
        try Data(#"[{"label":"account1","config_dir":"/tmp/account1"}]"#.utf8).write(to: file)
        let accounts = try AccountStore(fileURL: file).load()
        let again = try AccountStore(fileURL: file).load()
        XCTAssertEqual(accounts, again)
        XCTAssertEqual(accounts.first?.configDirectory, "/tmp/account1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        XCTAssertNotNil(json[0]["id"])
        XCTAssertEqual(json[0]["configDirectory"] as? String, "/tmp/account1")
        XCTAssertNil(json[0]["config_dir"])
    }

    func testCorruptFileIsBackedUpAndCannotBeOverwrittenBySave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("accounts.json")
        let invalid = Data("not JSON".utf8)
        try invalid.write(to: file)
        let store = AccountStore(fileURL: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("bak")), invalid)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("bak")), invalid)
    }

    func testMissingFileStartsEmptyAndCanBeSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        XCTAssertTrue(try store.load().isEmpty)
        try store.save([Account(label: "account1", configDirectory: "/tmp/account1")])
        XCTAssertEqual(try store.load().count, 1)
    }
}
