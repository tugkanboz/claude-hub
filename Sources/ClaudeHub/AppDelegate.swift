import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accountStore = AccountStore()
    private let client = AnthropicClient()
    private var accounts: [Account] = []
    private var states: [UUID: AccountState] = [:]
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var accountStoreAvailable = true
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = RefreshGeneration()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { accounts = try accountStore.load() } catch {
            accountStoreAvailable = false
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
        switch states[account.id] ?? .loading {
        case .loading:
            addDisabled(L10n.text(.loading), to: submenu)
        case .failed(let message):
            addDisabled(L10n.format(.error, message), to: submenu)
        case .loaded(let snapshot):
            if let email = snapshot.email { addDisabled(email, to: submenu) }
            if let expiry = snapshot.refreshTokenExpiresAt,
               expiry > 0, Double(expiry) / 1_000 - Date().timeIntervalSince1970 < 5 * 86_400 {
                addDisabled(L10n.text(.refreshTokenExpiring), to: submenu)
            }
            addWindow(L10n.text(.fiveHour), snapshot.usage.fiveHour, to: submenu)
            addWindow(L10n.text(.sevenDay), snapshot.usage.sevenDay, to: submenu)
            addWindow(L10n.text(.sevenDaySonnet), snapshot.usage.sevenDaySonnet, to: submenu)
            addWindow(L10n.text(.sevenDayOpus), snapshot.usage.sevenDayOpus, to: submenu)
            addWindow(L10n.text(.oauthApps), snapshot.usage.sevenDayOAuthApps, to: submenu)
            addWindow(L10n.text(.cowork), snapshot.usage.sevenDayCowork, to: submenu)
            if let extra = snapshot.usage.extraUsage.flatMap(UsageFormatting.extraUsage) {
                addDisabled(extra, to: submenu)
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            addDisabled(L10n.format(.updated, formatter.string(from: snapshot.fetchedAt)), to: submenu)
        }
        item.submenu = submenu
        return item
    }

    private func accountManagementMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: L10n.text(.addProfile), action: #selector(addAccountPressed), keyEquivalent: "")
        add.target = self
        add.isEnabled = accountStoreAvailable
        menu.addItem(add)

        if !accounts.isEmpty {
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
            await withTaskGroup(of: (UUID, AccountState).self) { group in
                for account in requestedAccounts {
                    group.addTask { [client] in
                        do {
                            try Task.checkCancellation()
                            return (account.id, .loaded(try await client.snapshot(for: account)))
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
                    rebuildMenu()
                }
            }
        }
    }

    @objc private func addAccountPressed() {
        guard accountStoreAvailable else { return }
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
            let credential = try CredentialStore().read(for: account)
            let updated = accounts + [account]
            try accountStore.save(updated)
            accounts = updated
            states[account.id] = .loading
            rebuildMenu()
            Task {
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
        let updated = accounts.filter { $0.id != id }
        do { try accountStore.save(updated) } catch {
            showError(error.localizedDescription)
            return
        }
        accounts = updated
        states[id] = nil
        Task { await client.forget(account) }
        refreshAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTimer?.invalidate()
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
