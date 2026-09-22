import Foundation

enum UsageJournalTable {
    static func render(_ entries: [UsageJournalEntry], language: AppLanguage) -> String {
        let includeCosts = entries.contains { $0.extraUsage?.isEnabled == true }
        var keys: [L10nKey] = [.journalTime, .journalMeasurement, .journalStatus, .journalPeriod, .journalPercent, .journalReset]
        if includeCosts { keys += [.journalSpent, .journalBudget] }
        let headers = keys.map { L10n.text($0, language: language) }
        var rows: [[String]] = []
        for entry in entries {
            let prefix = [UsageJournalSummary.timestamp(entry.scheduledAt),
                          entry.sampledAt.map(UsageJournalSummary.timestamp) ?? "-",
                          L10n.text(entry.status == "available" ? .journalAvailable : .journalMissing, language: language)]
            for window in entry.windows {
                var row = prefix + [period(window.name, language: language), percent(window.utilization), reset(window.resetsAt)]
                if includeCosts { row += ["-", "-"] }
                rows.append(row)
            }
            if let extra = entry.extraUsage, extra.isEnabled {
                rows.append(prefix + [L10n.text(.journalExtra, language: language), percent(extra.utilization), "-",
                                      money(extra.usedCredits), money(extra.monthlyLimit.map { Double($0) })])
            } else if entry.windows.isEmpty {
                rows.append(prefix + Array(repeating: "-", count: headers.count - prefix.count))
            }
        }
        let widths = headers.indices.map { column in
            max(headers[column].count, rows.map { $0[column].count }.max() ?? 0)
        }
        func line(_ cells: [String], numeric: Bool = false) -> String {
            "| " + cells.enumerated().map { column, value in
                let padding = String(repeating: " ", count: widths[column] - value.count)
                return numeric && [4, 6, 7].contains(column) ? padding + value : value + padding
            }.joined(separator: " | ") + " |"
        }
        let border = "|" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "|") + "|"
        return ([border, line(headers), border] + rows.map { line($0, numeric: true) } + [border]).joined(separator: "\n") + "\n"
    }

    private static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func money(_ cents: Double?) -> String {
        guard let cents, cents.isFinite else { return "-" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), cents / 100)
    }

    private static func reset(_ value: String?) -> String {
        guard let value else { return "-" }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return UsageJournalSummary.timestamp(date) }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value).map(UsageJournalSummary.timestamp) ?? "-"
    }

    private static func period(_ name: String, language: AppLanguage) -> String {
        let key: L10nKey
        switch name {
        case "five_hour": key = .fiveHour
        case "seven_day": key = .sevenDay
        case "seven_day_sonnet": key = .sevenDaySonnet
        case "seven_day_opus": key = .sevenDayOpus
        case "seven_day_oauth_apps": key = .oauthApps
        default: key = .cowork
        }
        return L10n.text(key, language: language)
    }
}
