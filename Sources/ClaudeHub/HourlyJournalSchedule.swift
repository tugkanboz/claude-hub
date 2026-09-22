import AppKit

enum HourBoundary {
    static func next(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
    }

    static func canRecord(scheduled: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let delay = now.timeIntervalSince(scheduled)
        return delay >= 0 && delay < 60 && calendar.component(.minute, from: now) == 0
    }
}

@MainActor
final class HourlyJournalSchedule: NSObject {
    private var timer: Timer?
    private var sleeping = false
    private var running = false
    private let record: @MainActor (Date) -> Void

    init(record: @escaping @MainActor (Date) -> Void) {
        self.record = record
        super.init()
    }

    func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        scheduleNext()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func willSleep() {
        sleeping = true
        timer?.invalidate()
        timer = nil
    }

    @objc private func didWake() {
        sleeping = false
        scheduleNext()
    }

    @objc private func clockChanged() { scheduleNext() }

    private func scheduleNext() {
        timer?.invalidate()
        guard running, !sleeping, let next = HourBoundary.next(after: Date()) else { return }
        let timer = Timer(fireAt: next, interval: 0, target: self, selector: #selector(fired(_:)), userInfo: next, repeats: false)
        timer.tolerance = 1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func fired(_ timer: Timer) {
        guard running, !sleeping, timer === self.timer else { return }
        if let scheduled = timer.userInfo as? Date, HourBoundary.canRecord(scheduled: scheduled, now: Date()) {
            record(scheduled)
        }
        scheduleNext()
    }
}
