import Foundation

enum RenewalPolicy {
    static func scheduledDate(for credential: OAuthCredential, now: Date, notBefore: Date? = nil) -> Date {
        let expiry = Date(timeIntervalSince1970: Double(credential.expiresAt) / 1_000)
        return max(now, expiry.addingTimeInterval(-600), notBefore ?? now)
    }

    static func retryDelay(failures: Int) -> TimeInterval {
        min(1_800, 300 * pow(2, Double(min(max(0, failures - 1), 3))))
    }
}

actor SessionCoordinator {
    typealias Renew = @Sendable (Account, OAuthCredential) async throws -> Void

    private let cache: CredentialCache
    private let renewAction: Renew
    private let automaticRenewal: Bool
    private var accounts: [UUID: Account] = [:]
    private var schedules: [UUID: (generation: UUID, task: Task<Void, Never>)] = [:]
    private var renewals: [UUID: Task<OAuthCredential, Error>] = [:]
    private var nextAllowed: [UUID: Date] = [:]
    private var failures: [UUID: Int] = [:]

    init(cache: CredentialCache, automaticRenewal: Bool = true,
         renew: @escaping Renew = { try await ClaudeLoginRefresher().renew(account: $0, credential: $1) }) {
        self.cache = cache
        self.automaticRenewal = automaticRenewal
        renewAction = renew
    }

    func configure(_ accounts: [Account]) {
        guard !Task.isCancelled else { return }
        let remaining = Set(accounts.map(\.id))
        for id in self.accounts.keys where !remaining.contains(id) {
            schedules.removeValue(forKey: id)?.task.cancel()
            renewals[id]?.cancel()
            nextAllowed[id] = nil
            failures[id] = nil
        }
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func credential(for account: Account) async throws -> OAuthCredential {
        guard accounts[account.id] != nil else { throw CancellationError() }
        let credential = try await cache.read(for: account)
        guard accounts[account.id] != nil else { throw CancellationError() }
        if schedules[account.id] == nil { schedule(account, credential: credential) }
        return credential
    }

    func reload(_ account: Account) async throws -> OAuthCredential {
        guard accounts[account.id] != nil else { throw CancellationError() }
        let credential = try await cache.reload(for: account)
        guard accounts[account.id] != nil else { throw CancellationError() }
        schedule(account, credential: credential)
        return credential
    }

    func reconnect(_ account: Account) async throws {
        if let pending = renewals[account.id] { _ = await pending.result }
        _ = try await reload(account)
        nextAllowed[account.id] = nil
        failures[account.id] = nil
        let credential = try await cache.read(for: account)
        schedule(account, credential: credential)
    }

    func remember(_ credential: OAuthCredential, for account: Account) async {
        await cache.remember(credential, for: account)
        if accounts[account.id] != nil { schedule(account, credential: credential) }
    }

    func forget(_ account: Account) async throws {
        accounts[account.id] = nil
        schedules.removeValue(forKey: account.id)?.task.cancel()
        if let task = renewals[account.id] {
            task.cancel()
            _ = await task.result
        }
        nextAllowed[account.id] = nil
        failures[account.id] = nil
        try await cache.remove(for: account)
    }

    func renew(_ account: Account, force: Bool = false) async throws -> OAuthCredential {
        guard accounts[account.id] != nil else { throw CancellationError() }
        if let pending = renewals[account.id] { return try await pending.value }
        if let next = nextAllowed[account.id], next > Date() { throw LoginRefreshError.failed }
        let task = Task { [cache, renewAction] in
            let credential = try await (force ? cache.read(for: account) : cache.reload(for: account))
            if !force, Double(credential.expiresAt) / 1_000 > Date().timeIntervalSince1970 + 600 {
                return credential
            }
            try Task.checkCancellation()
            try await renewAction(account, credential)
            try Task.checkCancellation()
            let renewed = try await cache.reload(for: account)
            guard renewed.accessToken != credential.accessToken || renewed.expiresAt > credential.expiresAt else {
                throw LoginRefreshError.failed
            }
            return renewed
        }
        renewals[account.id] = task
        do {
            let credential = try await task.value
            renewals[account.id] = nil
            guard accounts[account.id] != nil else { throw CancellationError() }
            failures[account.id] = 0
            nextAllowed[account.id] = Date().addingTimeInterval(60)
            schedule(account, credential: credential)
            return credential
        } catch {
            renewals[account.id] = nil
            if accounts[account.id] != nil {
                let count = (failures[account.id] ?? 0) + 1
                failures[account.id] = count
                nextAllowed[account.id] = Date().addingTimeInterval(RenewalPolicy.retryDelay(failures: count))
                if let current = try? await cache.read(for: account) { schedule(account, credential: current) }
            }
            throw error
        }
    }

    private func schedule(_ account: Account, credential: OAuthCredential) {
        guard automaticRenewal, accounts[account.id] != nil, credential.expiresAt > 0,
              credential.refreshToken?.isEmpty == false, credential.scopes?.isEmpty == false else { return }
        schedules[account.id]?.task.cancel()
        if let expiry = credential.refreshTokenExpiresAt, expiry > 0,
           Double(expiry) / 1_000 <= Date().timeIntervalSince1970 {
            schedules[account.id] = nil
            return
        }
        let due = RenewalPolicy.scheduledDate(for: credential, now: Date(), notBefore: nextAllowed[account.id])
        let generation = UUID()
        let task = Task { [weak self] in
            do {
                while due.timeIntervalSinceNow > 0 {
                    let delay = min(60, max(0.01, due.timeIntervalSinceNow))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                try Task.checkCancellation()
                await self?.scheduledRenewal(account, generation: generation)
            } catch { }
        }
        schedules[account.id] = (generation, task)
    }

    private func scheduledRenewal(_ account: Account, generation: UUID) async {
        guard schedules[account.id]?.generation == generation else { return }
        schedules[account.id] = nil
        guard accounts[account.id] != nil else { return }
        do { _ = try await renew(account) } catch {
            AppLogger.write("[warn] Scheduled session renewal failed; usage requests may still succeed")
        }
    }
}
