import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accountStore = AccountStore()
    private let client = AnthropicClient()
    private var accounts: [Account] = []
    private var states: [UUID: AccountState] = [:]
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        accounts = accountStore.load()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Claude Usage"
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.image = Self.menuIcon()
        rebuildMenu()
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
            addDisabled("Henüz hesap eklenmedi", to: menu)
        } else {
            for account in accounts { menu.addItem(accountMenuItem(account)) }
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Şimdi yenile", action: #selector(refreshPressed), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let accountsItem = NSMenuItem(title: "Hesaplar", action: nil, keyEquivalent: "")
        accountsItem.submenu = accountManagementMenu()
        menu.addItem(accountsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "ClaudeHub'dan çık", action: #selector(quitPressed), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func accountMenuItem(_ account: Account) -> NSMenuItem {
        let item = NSMenuItem(title: account.label, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        switch states[account.id] ?? .loading {
        case .loading:
            addDisabled("Yükleniyor…", to: submenu)
        case .failed(let message):
            addDisabled("Hata: \(message)", to: submenu)
        case .loaded(let snapshot):
            if let email = snapshot.email { addDisabled(email, to: submenu) }
            addWindow("5 saat", snapshot.usage.fiveHour, to: submenu)
            addWindow("7 gün", snapshot.usage.sevenDay, to: submenu)
            addWindow("7 gün Sonnet", snapshot.usage.sevenDaySonnet, to: submenu)
            addWindow("7 gün Opus", snapshot.usage.sevenDayOpus, to: submenu)
            addWindow("OAuth uygulamaları", snapshot.usage.sevenDayOAuthApps, to: submenu)
            addWindow("Cowork", snapshot.usage.sevenDayCowork, to: submenu)
            if let extra = snapshot.usage.extraUsage.flatMap(UsageFormatting.extraUsage) {
                addDisabled(extra, to: submenu)
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            addDisabled("Güncellendi: \(formatter.string(from: snapshot.fetchedAt))", to: submenu)
        }
        item.submenu = submenu
        return item
    }

    private func accountManagementMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "Claude profili ekle…", action: #selector(addAccountPressed), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        if !accounts.isEmpty {
            let remove = NSMenuItem(title: "Hesap kaldır", action: nil, keyEquivalent: "")
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
        for account in accounts { states[account.id] = .loading }
        rebuildMenu()
        Task {
            for account in accounts {
                do {
                    states[account.id] = .loaded(try await client.snapshot(for: account))
                } catch {
                    let message = error.localizedDescription
                    states[account.id] = .failed(message)
                    AppLogger.write("[warn] \(account.label): \(message)")
                }
                rebuildMenu()
            }
        }
    }

    @objc private func addAccountPressed() {
        let picker = NSOpenPanel()
        picker.title = "Claude Code profil klasörünü seç"
        picker.prompt = "Seç"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-accounts", isDirectory: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }

        let path = url.path
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".claude.json").path) else {
            showError("Bu klasörde .claude.json bulunamadı. Önce bu CLAUDE_CONFIG_DIR ile Claude Code'a giriş yap.")
            return
        }
        if accounts.contains(where: { $0.configDirectory == path }) {
            showError("Bu profil zaten ekli.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Hesap adı"
        alert.informativeText = "Menüde görünecek kısa adı yaz."
        alert.addButton(withTitle: "Ekle")
        alert.addButton(withTitle: "İptal")
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { showError("Hesap adı boş olamaz."); return }

        let account = Account(label: label, configDirectory: path)
        do {
            let credential = try CredentialStore().read(for: account)
            accounts.append(account)
            try accountStore.save(accounts)
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
        accounts.removeAll { $0.id == id }
        states[id] = nil
        Task { await client.forget(account) }
        do { try accountStore.save(accounts) } catch { showError(error.localizedDescription) }
        rebuildMenu()
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
