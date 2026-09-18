import Foundation

enum UsageFormatting {
    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackParser = ISO8601DateFormatter()

    static func line(name: String, window: UsageWindow) -> String {
        let percent = String(
            format: "%.1f%%",
            locale: L10n.language.locale,
            window.utilization
        )
        guard let rawDate = window.resetsAt,
              let date = parser.date(from: rawDate) ?? fallbackParser.date(from: rawDate)
        else {
            return L10n.format(.usageUsed, name, percent)
        }
        return "\(name): \(percent) · \(relativeReset(date))"
    }

    static func extraUsage(_ usage: ExtraUsage) -> String? {
        guard usage.isEnabled else { return nil }
        let used = (usage.usedCredits ?? 0) / 100
        if let limit = usage.monthlyLimit {
            return L10n.format(.extraUsageWithLimit, used, Double(limit) / 100)
        }
        return L10n.format(.extraUsage, used)
    }

    private static func relativeReset(_ date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)
        let hours = Int(interval) / 3_600
        let days = hours / 24
        if days > 0 { return L10n.format(.resetDaysHours, days, hours % 24) }
        if hours > 0 { return L10n.format(.resetHours, hours) }
        let minutes = max(1, Int(interval) / 60)
        return L10n.format(.resetMinutes, minutes)
    }
}
