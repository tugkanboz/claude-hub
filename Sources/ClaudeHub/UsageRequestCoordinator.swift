import Foundation

enum RateLimitPolicy {
    static func retryDate(header: String?, now: Date) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Double(value), seconds.isFinite {
            return min(Date.distantFuture, now.addingTimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func delay(failures: Int, jitter: Double) -> TimeInterval {
        let base = min(1_800, 60 * pow(2, Double(min(max(0, failures - 1), 5))))
        return min(1_800, base * (1 + min(0.2, max(0, jitter))))
    }
}

actor UsageRequestCoordinator {
    typealias Operation = @Sendable () async throws -> AccountSnapshot
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> Double
    private let cooldownStore: RateLimitStore?
    private var active: Set<UUID> = []
    private var paused: Set<UUID> = []
    private var requests: [UUID: (id: UUID, task: Task<AccountSnapshot, Error>)] = [:]
    private var retryDates: [UUID: Date] = [:]
    private var failures: [UUID: Int] = [:]
    private var recent: [UUID: (snapshot: AccountSnapshot, completedAt: Date)] = [:]

    init(now: @escaping @Sendable () -> Date = { Date() },
         jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...0.2) },
         cooldownStore: RateLimitStore? = nil) {
        self.now = now
        self.jitter = jitter
        self.cooldownStore = cooldownStore
    }

    func configure(_ accounts: [Account]) {
        let remaining = Set(accounts.map(\.id))
        for id in active.subtracting(remaining) { remove(id) }
        for id in remaining.subtracting(active) {
            do { retryDates[id] = try cooldownStore?.load(for: id, now: now()) }
            catch { AppLogger.write("[warn] Could not load 429 cooldown account=\(id)") }
        }
        active = remaining
    }

    func snapshot(for account: Account, operation: @escaping Operation) async throws -> AccountSnapshot {
        try Task.checkCancellation()
        let id = account.id
        guard active.contains(id), !paused.contains(id) else { throw CancellationError() }
        if let retry = retryDates[id], retry > now() { throw AnthropicClientError.rateLimited(until: retry) }
        if let cached = recent[id], now().timeIntervalSince(cached.completedAt) >= 0,
           now().timeIntervalSince(cached.completedAt) < 30 { return cached.snapshot }
        let pending: Task<AccountSnapshot, Error>
        if let existing = requests[id] {
            pending = existing.task
        } else {
            let generation = UUID()
            pending = Task { try await self.perform(account, generation: generation, operation: operation) }
            requests[id] = (generation, pending)
        }
        // Cancelling one UI refresh must not cancel a request shared by its replacement.
        let result = try await pending.value
        try Task.checkCancellation()
        return result
    }

    private func perform(_ account: Account, generation: UUID, operation: Operation) async throws -> AccountSnapshot {
        let id = account.id
        defer { if requests[id]?.id == generation { requests[id] = nil } }
        do {
            let snapshot = try await operation()
            try Task.checkCancellation()
            guard active.contains(id), requests[id]?.id == generation else { throw CancellationError() }
            retryDates[id] = nil
            failures[id] = nil
            recent[id] = (snapshot, now())
            do { try cooldownStore?.remove(for: id) }
            catch { AppLogger.write("[warn] Could not clear 429 cooldown account=\(id)") }
            return snapshot
        } catch {
            guard active.contains(id), requests[id]?.id == generation else { throw CancellationError() }
            let endpoint: String
            let suggested: Date?
            switch error {
            case AnthropicClientError.rateLimitResponse(let path, let retry):
                endpoint = path.rawValue
                suggested = retry
            case AnthropicClientError.http(429):
                endpoint = "unknown"
                suggested = nil
            default: throw error
            }
            let count = min((failures[id] ?? 0) + 1, 10)
            failures[id] = count
            let date = now()
            let retry = suggested.map { max(date.addingTimeInterval(1), $0) }
                ?? date.addingTimeInterval(RateLimitPolicy.delay(failures: count, jitter: jitter()))
            retryDates[id] = retry
            do { try cooldownStore?.save(retry, for: id) }
            catch { AppLogger.write("[warn] Could not save 429 cooldown account=\(id)") }
            AppLogger.write("[warn] HTTP 429 account=\(id) endpoint=\(endpoint) retryAt=\(ISO8601DateFormatter().string(from: retry))")
            throw AnthropicClientError.rateLimited(until: retry)
        }
    }

    func pause(_ account: Account) async {
        paused.insert(account.id)
        let task = requests.removeValue(forKey: account.id)?.task
        task?.cancel()
        recent[account.id] = nil
        _ = await task?.result
    }

    func resume(_ account: Account) { paused.remove(account.id) }

    func remove(_ id: UUID) {
        active.remove(id)
        paused.remove(id)
        requests.removeValue(forKey: id)?.task.cancel()
        retryDates[id] = nil
        failures[id] = nil
        recent[id] = nil
        do { try cooldownStore?.remove(for: id) }
        catch { AppLogger.write("[warn] Could not remove 429 cooldown account=\(id)") }
    }
}
