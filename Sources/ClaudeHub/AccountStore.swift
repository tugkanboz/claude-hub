import Foundation

final class AccountStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ClaudeHub", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("accounts.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [Account] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([Account].self, from: data)) ?? []
    }

    func save(_ accounts: [Account]) throws {
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }
}
