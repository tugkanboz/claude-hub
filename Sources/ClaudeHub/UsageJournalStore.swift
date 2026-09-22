import Foundation

actor UsageJournalStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-usage/ClaudeHub", isDirectory: true)
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var loaded: Set<UUID> = []
    private var previous: [UUID: UsageJournalEntry] = [:]
    private var previousSuccess: [UUID: UsageJournalEntry] = [:]
    private var days: [UUID: (name: String, entries: [UsageJournalEntry])] = [:]
    private var cleanupDay: String?

    init(directory: URL = UsageJournalStore.directory) {
        root = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func record(accountID: UUID, scheduled: Date, now: Date, snapshot: AccountSnapshot?, language: AppLanguage) throws {
        try prepare(root)
        try prune(now: now)
        let directory = root.appendingPathComponent(accountID.uuidString, isDirectory: true)
        try prepare(directory)
        let day = Self.dayName(scheduled)
        let file = directory.appendingPathComponent(day + ".json")
        if !loaded.contains(accountID) {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
                .filter { $0.pathExtension == "json" && Self.dayDate($0.deletingPathExtension().lastPathComponent) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for candidate in files {
                let entries = try read(candidate, accountID: accountID).filter { $0.scheduledAt < scheduled }
                if previous[accountID] == nil { previous[accountID] = entries.max { $0.scheduledAt < $1.scheduledAt } }
                if previousSuccess[accountID] == nil {
                    previousSuccess[accountID] = entries.filter { $0.status == "available" }.max { $0.scheduledAt < $1.scheduledAt }
                }
                if previous[accountID] != nil && previousSuccess[accountID] != nil { break }
            }
            loaded.insert(accountID)
        }
        var entries: [UsageJournalEntry]
        if days[accountID]?.name == day {
            entries = days[accountID]!.entries
        } else {
            entries = try read(file, accountID: accountID)
        }
        if !entries.contains(where: { $0.scheduledAt == scheduled }) {
            let prior = previous[accountID].flatMap { $0.scheduledAt < scheduled ? $0 : nil }
            let success = previousSuccess[accountID].flatMap { $0.scheduledAt < scheduled ? $0 : nil }
            let entry = UsageJournalSummary.entry(accountID: accountID, scheduled: scheduled, now: now,
                snapshot: snapshot, previous: prior, previousSuccess: success, language: language)
            entries.append(entry)
            entries.sort { $0.scheduledAt < $1.scheduledAt }
            try write(encoder.encode(entries), to: file)
            previous[accountID] = entry
            if entry.status == "available" { previousSuccess[accountID] = entry }
        }
        days[accountID] = (day, entries)
        let readable = entries.map { entry in
            "\(UsageJournalSummary.timestamp(entry.scheduledAt)) · ClaudeHub · \(entry.accountID.uuidString.prefix(8))\n"
                + entry.summary.map { "  " + $0 }.joined(separator: "\n") + "\n"
        }.joined(separator: "\n")
        try write(Data(readable.utf8), to: directory.appendingPathComponent(day + ".log"))
    }

    private func read(_ file: URL, accountID: UUID) throws -> [UsageJournalEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        try rejectSymlink(file)
        let entries = try decoder.decode([UsageJournalEntry].self, from: Data(contentsOf: file))
        guard entries.allSatisfy({ $0.accountID == accountID && $0.schemaVersion == 1 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries
    }

    private func prepare(_ directory: URL) throws {
        try rejectSymlink(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func rejectSymlink(_ file: URL) throws {
        if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func write(_ data: Data, to file: URL) throws {
        try rejectSymlink(file)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func prune(now: Date) throws {
        let day = Self.dayName(now)
        guard cleanupDay != day else { return }
        let cutoff = Self.dayDate(day)!.addingTimeInterval(-29 * 86_400)
        let manager = FileManager.default
        for directory in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
                guard ["json", "log"].contains(file.pathExtension),
                      let date = Self.dayDate(file.deletingPathExtension().lastPathComponent), date < cutoff else { continue }
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                try manager.removeItem(at: file)
            }
        }
        cleanupDay = day
    }

    private static func dayName(_ date: Date) -> String { String(UsageJournalSummary.utcTimestamp(date).prefix(10)) }

    private static func dayDate(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return ISO8601DateFormatter().date(from: value + "T00:00:00Z")
    }
}
