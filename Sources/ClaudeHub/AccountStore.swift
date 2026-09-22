import Foundation

final class AccountStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var loadFailed = false

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ClaudeHub", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("accounts.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> [Account] {
        do {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                loadFailed = false
                return []
            }
            let accounts: [Account]
            do {
                accounts = try decoder.decode([Account].self, from: data)
            } catch {
                let backup = fileURL.appendingPathExtension("bak")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try data.write(to: backup, options: .withoutOverwriting)
                } else {
                    try data.write(to: fileURL.appendingPathExtension("\(UUID().uuidString).bak"), options: .withoutOverwriting)
                }
                throw error
            }
            loadFailed = false
            try save(accounts)
            return accounts
        } catch {
            loadFailed = true
            AppLogger.write("[warn] Could not load or normalize accounts.json; original file preserved")
            throw AccountStoreError.unavailable
        }
    }

    func save(_ accounts: [Account]) throws {
        guard !loadFailed else { throw AccountStoreError.unavailable }
        let data = try encoder.encode(accounts)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum AccountStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { L10n.text(.accountStoreUnavailable) }
}
