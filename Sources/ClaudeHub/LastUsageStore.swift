import Foundation

struct LastUsageStore {
    private struct Entry: Codable {
        let accountID: UUID
        let fetchedAt: Date
        let usage: UsagePayload
    }

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeHub/LastUsage", isDirectory: true)
    }

    func load(for account: Account, now: Date = Date()) throws -> AccountSnapshot? {
        try rejectSymlink(directory)
        let file = path(for: account)
        try rejectSymlink(file)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
        guard entry.accountID == account.id,
              entry.fetchedAt <= now.addingTimeInterval(60),
              entry.fetchedAt >= now.addingTimeInterval(-7 * 86_400) else { return nil }
        return AccountSnapshot(email: nil, organizationID: nil, usage: entry.usage, fetchedAt: entry.fetchedAt)
    }

    func save(_ snapshot: AccountSnapshot, for account: Account) throws {
        try rejectSymlink(directory.deletingLastPathComponent())
        try rejectSymlink(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let file = path(for: account)
        try rejectSymlink(file)
        let data = try JSONEncoder().encode(Entry(accountID: account.id,
                                                  fetchedAt: snapshot.fetchedAt, usage: snapshot.usage))
        try data.write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(for account: Account) throws {
        try rejectSymlink(directory)
        let file = path(for: account)
        try rejectSymlink(file)
        if fileManager.fileExists(atPath: file.path) { try fileManager.removeItem(at: file) }
    }

    private func path(for account: Account) -> URL {
        directory.appendingPathComponent(account.id.uuidString + ".json")
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
