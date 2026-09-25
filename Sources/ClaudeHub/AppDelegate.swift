import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accountStore = AccountStore()
    private let client = AnthropicClient(requests: UsageRequestCoordinator(cooldownStore: RateLimitStore()))
    private var accounts: [Account] = []
    private var permissionRequired: Set<UUID> = []
    private var authorizationInProgress = false
    private var lastSnapshots: [UUID: AccountSnapshot] = [:]
    private var states: [UUID: AccountState] = [:]
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var accountStoreAvailable = true
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = RefreshGeneration()
    private let lastUsageStore = LastUsageStore()
    private let usageJournal = UsageJournalStore()
    private var journalSchedule: HourlyJournalSchedule?
    private var journalSamples: [UUID: AccountSnapshot] = [:]
    private var journalFailures: Set<UUID> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(permissionChanged(_:)), name: .credentialPermissionRequired, object: nil)
        do { accounts = try accountStore.load() } catch {
            accountStoreAvailable = false
        }
        for account in accounts {
            do { lastSnapshots[account.id] = try lastUsageStore.load(for: account) }
            catch { AppLogger.write("[warn] Could not load last usage account=\(account.id)") }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "ClaudeHub"
        statusItem.button?.setAccessibilityLabel("ClaudeHub")
        statusItem.button?.image = Self.menuIcon()
        rebuildMenu()
        if !accountStoreAvailable { showError(L10n.text(.accountStoreUnavailable)) }
        refreshAll()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 300,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        journalSchedule = HourlyJournalSchedule { [weak self] scheduled in self?.recordHourlyUsage(scheduled) }
        journalSchedule?.start()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        addDisabled("ClaudeHub", to: menu)
        menu.addItem(.separator())

        if accounts.isEmpty {
            addDisabled(L10n.text(.noAccounts), to: menu)
        } else {
            for account in accounts { menu.addItem(accountMenuItem(account)) }
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: L10n.text(.refreshNow), action: #selector(refreshPressed), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let accountsItem = NSMenuItem(title: L10n.text(.accounts), action: nil, keyEquivalent: "")
        accountsItem.submenu = accountManagementMenu()
        menu.addItem(accountsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.text(.quit), action: #selector(quitPressed), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func accountMenuItem(_ account: Account) -> NSMenuItem {
        let item = NSMenuItem(title: account.label, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if permissionRequired.contains(account.id) {
            addDisabled(L10n.text(.credentialPermissionRequired), to: submenu)
            let allow = NSMenuItem(title: L10n.text(.grantCredentialAccess), action: #selector(reconnectAccountPressed(_:)), keyEquivalent: "")
            allow.target = self
            allow.representedObject = account.id.uuidString
            submenu.addItem(allow)
            submenu.addItem(.separator())
        }
        switch states[account.id] ?? .loading {
        case .loading:
            addDisabled(L10n.text(.loading), to: submenu)
            addLastSnapshot(for: account, to: submenu)
        case .failed(let message):
            if !permissionRequired.contains(account.id) {
                addDisabled(L10n.format(.error, message), to: submenu)
            }
            addLastSnapshot(for: account, to: submenu)
        case .rateLimited(let retry):
            addDisabled(AnthropicClientError.rateLimited(until: retry).localizedDescription, to: submenu)
            addLastSnapshot(for: account, to: submenu)
        case .loaded(let snapshot):
            addSnapshot(snapshot, to: submenu)
        }
        submenu.addItem(.separator())
        if journalFailures.contains(account.id) { addDisabled(L10n.text(.journalWriteFailed), to: submenu) }
        let journal = NSMenuItem(title: L10n.text(.journalOpen), action: #selector(openJournalPressed(_:)), keyEquivalent: "")
        journal.target = self
        journal.representedObject = account.id.uuidString
        submenu.addItem(journal)
        item.submenu = submenu
        return item
    }

    private func addLastSnapshot(for account: Account, to menu: NSMenu) {
        guard let snapshot = lastSnapshots[account.id] else { return }
        addDisabled(L10n.text(.lastKnownUsage), to: menu)
        addSnapshot(snapshot, to: menu)
    }

    private func addSnapshot(_ snapshot: AccountSnapshot, to menu: NSMenu) {
        if let email = snapshot.email { addDisabled(email, to: menu) }
        if OAuthCredential.needsRefreshTokenWarning(expiresAt: snapshot.refreshTokenExpiresAt) {
            addDisabled(L10n.text(.refreshTokenExpiring), to: menu)
        }
        addWindow(L10n.text(.fiveHour), snapshot.usage.fiveHour, to: menu)
        addWindow(L10n.text(.sevenDay), snapshot.usage.sevenDay, to: menu)
        addWindow(L10n.text(.sevenDaySonnet), snapshot.usage.sevenDaySonnet, to: menu)
        addWindow(L10n.text(.sevenDayOpus), snapshot.usage.sevenDayOpus, to: menu)
        addWindow(L10n.text(.oauthApps), snapshot.usage.sevenDayOAuthApps, to: menu)
        addWindow(L10n.text(.cowork), snapshot.usage.sevenDayCowork, to: menu)
        if let extra = snapshot.usage.extraUsage.flatMap(UsageFormatting.extraUsage) {
            addDisabled(extra, to: menu)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        addDisabled(L10n.format(.updated, formatter.string(from: snapshot.fetchedAt)), to: menu)
    }

    @objc private func permissionChanged(_ notification: Notification) {
        guard let id = notification.object as? UUID,
              let account = accounts.first(where: { $0.id == id }) else { return }
        Task {
            let required = await client.requiresPermission(for: account)
            guard accounts.contains(where: { $0.id == id }) else { return }
            if required { permissionRequired.insert(id) } else { permissionRequired.remove(id) }
            rebuildMenu()
        }
    }

    private func accountManagementMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let add = NSMenuItem(title: L10n.text(.addProfile), action: #selector(addAccountPressed), keyEquivalent: "")
        add.target = self
        add.isEnabled = accountStoreAvailable
        menu.addItem(add)

        if !accounts.isEmpty {
            let reconnect = NSMenuItem(title: L10n.text(.reconnectProfile), action: nil, keyEquivalent: "")
            let reconnectMenu = NSMenu()
            for account in accounts {
                let candidate = NSMenuItem(title: account.label, action: #selector(reconnectAccountPressed(_:)), keyEquivalent: "")
                candidate.target = self
                candidate.representedObject = account.id.uuidString
                reconnectMenu.addItem(candidate)
            }
            reconnect.submenu = reconnectMenu
            menu.addItem(reconnect)
            let remove = NSMenuItem(title: L10n.text(.removeAccount), action: nil, keyEquivalent: "")
            let removeMenu = NSMenu()
            for account in accounts {
                let candidate = NSMenuItem(
                    title: account.label,
                    action: #selector(removeAccountPressed(_:)),
                    keyEquivalent: ""
                )
                candidate.target = self
                candidate.representedObject = account.id.uuidString
                removeMenu.addItem(candidate)
            }
            remove.submenu = removeMenu
            menu.addItem(remove)
        }
        return menu
    }

    @objc private func refreshPressed() { refreshAll() }

    @objc private func timerFired() { refreshAll() }

    private func refreshAll() {
        refreshTask?.cancel()
        let generation = refreshGeneration.advance()
        let requestedAccounts = accounts
        for account in accounts { states[account.id] = .loading }
        rebuildMenu()
        refreshTask = Task {
            guard !Task.isCancelled else { return }
            await client.configure(accounts: requestedAccounts)
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: (UUID, AccountState).self) { group in
                for account in requestedAccounts {
                    group.addTask { [client] in
                        do {
                            try Task.checkCancellation()
                            return (account.id, .loaded(try await client.snapshot(for: account)))
                        } catch AnthropicClientError.rateLimited(let retry) {
                            return (account.id, .rateLimited(retry))
                        } catch {
                            return (account.id, .failed(error.localizedDescription))
                        }
                    }
                }
                for await (id, state) in group {
                    guard !Task.isCancelled,
                          refreshGeneration.accepts(generation),
                          accounts.contains(where: { $0.id == id }) else { continue }
                    states[id] = state
                    if case .loaded(let snapshot) = state {
                        lastSnapshots[id] = snapshot
                        journalSamples[id] = snapshot
                        if let account = accounts.first(where: { $0.id == id }) {
                            do { try lastUsageStore.save(snapshot, for: account) }
                            catch { AppLogger.write("[warn] Could not save last usage account=\(id)") }
                        }
                    } else {
                        journalSamples[id] = nil
                    }
                    rebuildMenu()
                }
            }
        }
    }

    @objc private func addAccountPressed() {
        guard accountStoreAvailable, !authorizationInProgress else { return }
        let picker = NSOpenPanel()
        picker.title = L10n.text(.pickerTitle)
        picker.prompt = L10n.text(.select)
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-accounts", isDirectory: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }

        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = normalizedURL.path
        guard FileManager.default.fileExists(atPath: normalizedURL.appendingPathComponent(".claude.json").path) else {
            showError(L10n.text(.missingClaudeJSON))
            return
        }
        if accounts.contains(where: {
            URL(fileURLWithPath: $0.configDirectory).standardizedFileURL.resolvingSymlinksInPath().path == path
        }) {
            showError(L10n.text(.profileAlreadyAdded))
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.text(.accountName)
        alert.informativeText = L10n.text(.accountNameHelp)
        alert.addButton(withTitle: L10n.text(.add))
        alert.addButton(withTitle: L10n.text(.cancel))
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { showError(L10n.text(.accountNameEmpty)); return }

        let account = Account(label: label, configDirectory: path)
        do {
            let credential = try CredentialStore().read(for: account, interaction: .userInitiated)
            let updated = accounts + [account]
            try accountStore.save(updated)
            accounts = updated
            states[account.id] = .loading
            rebuildMenu()
            Task {
                guard accounts.contains(where: { $0.id == account.id }) else { return }
                await client.remember(credential, for: account)
                refreshAll()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func removeAccountPressed(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let account = accounts.first(where: { $0.id == id })
        else { return }
        let confirmation = NSAlert()
        confirmation.messageText = L10n.format(.confirmRemoveAccount, account.label)
        confirmation.informativeText = L10n.text(.removeAccountHelp)
        confirmation.addButton(withTitle: L10n.text(.cancel))
        confirmation.addButton(withTitle: L10n.text(.removeAccount))
        guard confirmation.runModal() == .alertSecondButtonReturn else { return }
        let updated = accounts.filter { $0.id != id }
        do { try accountStore.save(updated) } catch {
            showError(error.localizedDescription)
            return
        }
        accounts = updated
        states[id] = nil
        lastSnapshots[id] = nil
        permissionRequired.remove(id)
        journalSamples[id] = nil
        journalFailures.remove(id)
        do { try lastUsageStore.remove(for: account) }
        catch { AppLogger.write("[warn] Could not remove last usage account=\(id)") }
        Task {
            do { try await client.forget(account) } catch {
                showError(L10n.text(.credentialCleanupFailed))
            }
        }
        refreshAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTimer?.invalidate()
        journalSchedule?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func recordHourlyUsage(_ scheduled: Date) {
        let now = Date()
        let samples = accounts.map { ($0.id, journalSamples[$0.id]) }
        let language = L10n.language
        Task {
            for (id, snapshot) in samples {
                do {
                    try await usageJournal.record(accountID: id, scheduled: scheduled, now: now, snapshot: snapshot, language: language)
                    journalFailures.remove(id)
                } catch {
                    if accounts.contains(where: { $0.id == id }) { journalFailures.insert(id) }
                    AppLogger.write("[warn] Could not write hourly usage journal; existing records preserved")
                }
            }
            rebuildMenu()
        }
    }

    @objc private func openJournalPressed(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String, let id = UUID(uuidString: rawID),
              accounts.contains(where: { $0.id == id }) else { return }
        let directory = UsageJournalStore.directory.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !NSWorkspace.shared.open(directory) { showError(L10n.text(.journalWriteFailed)) }
        } catch { showError(L10n.text(.journalWriteFailed)) }
    }

    @objc private func reconnectAccountPressed(_ sender: NSMenuItem) {
        guard !authorizationInProgress,
              let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let account = accounts.first(where: { $0.id == id }) else { return }
        journalSamples[id] = nil
        authorizationInProgress = true
        Task {
            defer { authorizationInProgress = false }
            do {
                try await client.reconnect(account)
                permissionRequired.remove(id)
                refreshAll()
            } catch is CancellationError { } catch {
                if CredentialStoreError.requiresPermission(error) {
                    permissionRequired.insert(id)
                    rebuildMenu()
                } else { showError(error.localizedDescription) }
            }
        }
    }

    @objc private func quitPressed() { NSApplication.shared.terminate(nil) }

    private func addWindow(_ name: String, _ window: UsageWindow?, to menu: NSMenu) {
        guard let window else { return }
        addDisabled(UsageFormatting.line(name: name, window: window), to: menu)
    }

    private func addDisabled(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ClaudeHub"
        alert.informativeText = message
        alert.runModal()
    }

    private static func menuIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            let path = NSBezierPath()
            path.lineWidth = 1.7
            path.move(to: NSPoint(x: 4, y: 5))
            path.line(to: NSPoint(x: 9, y: 13))
            path.line(to: NSPoint(x: 14, y: 5))
            path.stroke()
            for point in [NSPoint(x: 4, y: 5), NSPoint(x: 9, y: 13), NSPoint(x: 14, y: 5)] {
                NSBezierPath(ovalIn: NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
