import Foundation

enum UsageFormatting {
    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackParser = ISO8601DateFormatter()

    static func line(name: String, window: UsageWindow, now: Date = Date(), language: AppLanguage = L10n.language) -> String {
        let percent = String(
            format: "%.1f%%",
            locale: language.locale,
            window.utilization
        )
        guard let rawDate = window.resetsAt,
              let date = parser.date(from: rawDate) ?? fallbackParser.date(from: rawDate)
        else {
            return L10n.format(.usageUsed, name, percent, language: language)
        }
        return "\(name): \(percent) · \(relativeReset(date, now: now, language: language))"
    }

    static func extraUsage(_ usage: ExtraUsage) -> String? {
        extraUsage(usage, language: L10n.language)
    }

    static func extraUsage(_ usage: ExtraUsage, language: AppLanguage) -> String? {
        guard usage.isEnabled else { return nil }
        let used = (usage.usedCredits ?? 0) / 100
        if let limit = usage.monthlyLimit {
            return L10n.format(.extraUsageWithLimit, used, Double(limit) / 100, language: language)
        }
        return L10n.format(.extraUsage, used, language: language)
    }

    private static func relativeReset(_ date: Date, now: Date, language: AppLanguage) -> String {
        let interval = max(0, date.timeIntervalSince(now))
        let hours = Int(interval) / 3_600
        let days = hours / 24
        if days > 0 { return L10n.format(.resetDaysHours, days, hours % 24, language: language) }
        if hours > 0 { return L10n.format(.resetHours, hours, language: language) }
        let minutes = max(1, Int(interval) / 60)
        return L10n.format(.resetMinutes, minutes, language: language)
    }
}
