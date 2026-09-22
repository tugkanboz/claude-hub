import Foundation
import Darwin

enum LoginRefreshError: LocalizedError {
    case missingRefreshToken
    case missingScopes
    case cliNotFound
    case failed
    case defaultProfileProtected

    var errorDescription: String? {
        switch self {
        case .missingRefreshToken:
            return L10n.text(.missingRefreshToken)
        case .missingScopes:
            return L10n.text(.missingScopes)
        case .cliNotFound:
            return L10n.text(.cliNotFound)
        case .failed:
            return L10n.text(.loginRefreshFailed)
        case .defaultProfileProtected:
            return L10n.text(.defaultProfileProtected)
        }
    }
}

struct ClaudeLoginRefresher {
    func renew(account: Account, credential: OAuthCredential) async throws {
        guard !Self.isDefaultProfile(account.configDirectory) else {
            throw LoginRefreshError.defaultProfileProtected
        }
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw LoginRefreshError.missingRefreshToken
        }
        guard let scopes = credential.scopes, !scopes.isEmpty else {
            throw LoginRefreshError.missingScopes
        }
        guard let executable = Self.findClaudeExecutable() else {
            throw LoginRefreshError.cliNotFound
        }

        let execution = LoginProcessExecution()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = ["auth", "login", "--claudeai"]
                    var environment = ProcessInfo.processInfo.environment
                    environment["CLAUDE_CONFIG_DIR"] = account.configDirectory
                    environment["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = refreshToken
                    environment["CLAUDE_CODE_OAUTH_SCOPES"] = scopes.joined(separator: " ")
                    process.environment = environment
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice

                    do {
                        try execution.run(process, timeout: 60)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            execution.cancel()
        }
    }

    static func isDefaultProfile(_ path: String) -> Bool {
        let normal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            == normal.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func findClaudeExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

final class LoginProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func run(_ process: Process, timeout: TimeInterval) throws {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        self.process = process
        do { try process.run() } catch {
            self.process = nil
            lock.unlock()
            throw error
        }
        lock.unlock()
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            lock.lock()
            let stopped = cancelled
            lock.unlock()
            if stopped || Date() >= deadline {
                timedOut = !stopped
                if process.isRunning { process.terminate() }
                if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                break
            }
        }
        lock.lock()
        self.process = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard !timedOut, process.terminationStatus == 0 else { throw LoginRefreshError.failed }
    }
}
