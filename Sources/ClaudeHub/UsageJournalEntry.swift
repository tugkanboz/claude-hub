import Foundation

struct JournalWindow: Codable {
    let name: String
    let utilization: Double
    let resetsAt: String?
}

struct UsageJournalEntry: Codable {
    let schemaVersion: Int
    let accountID: UUID
    let scheduledAt: Date
    let recordedAt: Date
    let sampledAt: Date?
    let status: String
    let language: String
    let windows: [JournalWindow]
    let extraUsage: ExtraUsage?
    let summary: [String]
}

enum UsageJournalSummary {
    static func entry(accountID: UUID, scheduled: Date, now: Date, snapshot: AccountSnapshot?,
                      previous: UsageJournalEntry?, previousSuccess: UsageJournalEntry?,
                      language: AppLanguage) -> UsageJournalEntry {
        let fresh = snapshot.flatMap { sample -> AccountSnapshot? in
            let age = now.timeIntervalSince(sample.fetchedAt)
            return age >= 0 && age <= 360 ? sample : nil
        }
        let windows = fresh.map { windows(from: $0.usage) } ?? []
        var summary: [String] = []
        if let fresh {
            summary.append(L10n.format(.journalSampled, timestamp(fresh.fetchedAt), language: language))
            if let previousSuccess {
                let hours = scheduled.timeIntervalSince(previousSuccess.scheduledAt) / 3_600
                if hours > 1.01 {
                    summary.append(L10n.format(.journalGap, hours, language: language))
                }
            } else {
                summary.append(L10n.text(.journalFirst, language: language))
            }
            if previous?.status == "unavailable" {
                summary.append(L10n.text(.journalRecovered, language: language))
            }
            let continuous = previous?.status == "available"
                && previous.map { scheduled.timeIntervalSince($0.scheduledAt) <= 3_660 } == true
            for window in windows {
                let old = continuous ? previousSuccess?.windows.first(where: { $0.name == window.name }) : nil
                let name = L10n.text(key(for: window.name), language: language)
                summary.append(L10n.format(.journalWindow, name, window.utilization,
                    window.resetsAt.flatMap(parse).map(timestamp) ?? L10n.text(.journalUnknownReset, language: language), language: language))
                if let old, let oldReset = old.resetsAt.flatMap(parse), let reset = window.resetsAt.flatMap(parse) {
                    if reset != oldReset {
                        let newPeriod = reset > oldReset && oldReset <= fresh.fetchedAt
                        summary.append(L10n.text(newPeriod ? .journalNewPeriod : .journalResetChanged, language: language))
                    } else {
                        let delta = window.utilization - old.utilization
                        if abs(delta) < 0.05 {
                            summary.append(L10n.text(.journalUnchanged, language: language))
                        } else {
                            summary.append(L10n.format(delta > 0 ? .journalIncrease : .journalDecrease,
                                old.utilization, window.utilization, abs(delta), language: language))
                        }
                    }
                }
                if window.utilization >= 100 {
                    summary.append(L10n.text(.journalLimitReached, language: language))
                } else if window.utilization >= 80 {
                    summary.append(L10n.format(.journalNearLimit, max(0, 100 - window.utilization), language: language))
                }
            }
            if windows.isEmpty { summary.append(L10n.text(.journalNoWindows, language: language)) }
            if let extra = fresh.usage.extraUsage.flatMap({ UsageFormatting.extraUsage($0, language: language) }) {
                summary.append(extra)
            }
        } else {
            summary.append(L10n.text(.journalUnavailable, language: language))
        }
        return UsageJournalEntry(schemaVersion: 1, accountID: accountID, scheduledAt: scheduled, recordedAt: now,
            sampledAt: fresh?.fetchedAt, status: fresh == nil ? "unavailable" : "available", language: language.rawValue,
            windows: windows, extraUsage: fresh?.usage.extraUsage, summary: summary)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: date)
    }

    static func utcTimestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private static func parse(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value)
    }

    private static func windows(from usage: UsagePayload) -> [JournalWindow] {
        let values: [(String, UsageWindow?)] = [
            ("five_hour", usage.fiveHour), ("seven_day", usage.sevenDay),
            ("seven_day_sonnet", usage.sevenDaySonnet), ("seven_day_opus", usage.sevenDayOpus),
            ("seven_day_oauth_apps", usage.sevenDayOAuthApps), ("seven_day_cowork", usage.sevenDayCowork),
        ]
        return values.compactMap { name, window in
            guard let window, window.utilization.isFinite else { return nil }
            return JournalWindow(name: name, utilization: window.utilization, resetsAt: window.resetsAt)
        }
    }

    private static func key(for name: String) -> L10nKey {
        switch name {
        case "five_hour": return .fiveHour
        case "seven_day": return .sevenDay
        case "seven_day_sonnet": return .sevenDaySonnet
        case "seven_day_opus": return .sevenDayOpus
        case "seven_day_oauth_apps": return .oauthApps
        default: return .cowork
        }
    }
}
