import Foundation

struct RateLimitStore {
    static var profile: RateLimitStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeHub/ProfileRateLimits", isDirectory: true)
        return RateLimitStore(directory: directory)
    }

    private struct Entry: Codable {
        let accountID: UUID
        let retryAt: Date
    }

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeHub/RateLimits", isDirectory: true)
    }

    func load(for id: UUID, now: Date) throws -> Date? {
        try rejectSymlink(directory)
        let file = path(for: id)
        try rejectSymlink(file)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 4_096 else { throw CocoaError(.fileReadCorruptFile) }
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
        guard entry.accountID == id, entry.retryAt > now else { return nil }
        return entry.retryAt
    }

    func save(_ retryAt: Date, for id: UUID) throws {
        try rejectSymlink(directory.deletingLastPathComponent())
        try rejectSymlink(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let file = path(for: id)
        try rejectSymlink(file)
        try JSONEncoder().encode(Entry(accountID: id, retryAt: retryAt)).write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(for id: UUID) throws {
        try rejectSymlink(directory)
        let file = path(for: id)
        try rejectSymlink(file)
        if fileManager.fileExists(atPath: file.path) { try fileManager.removeItem(at: file) }
    }

    private func path(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
