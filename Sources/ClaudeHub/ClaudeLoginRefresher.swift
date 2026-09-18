import Foundation

enum LoginRefreshError: LocalizedError {
    case missingRefreshToken
    case missingScopes
    case cliNotFound
    case failed

    var errorDescription: String? {
        switch self {
        case .missingRefreshToken:
            return "Refresh token yok; bu profil için bir kez claude auth login çalıştır."
        case .missingScopes:
            return "OAuth scope bilgisi yok; bu profil için bir kez claude auth login çalıştır."
        case .cliNotFound:
            return "Claude Code bulunamadı. Claude Code'u kurup ClaudeHub'ı yeniden aç."
        case .failed:
            return "Claude Code oturumu yenileyemedi; bu profil için bir kez claude auth login çalıştır."
        }
    }
}

struct ClaudeLoginRefresher {
    func renew(account: Account, credential: OAuthCredential) async throws {
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw LoginRefreshError.missingRefreshToken
        }
        guard let scopes = credential.scopes, !scopes.isEmpty else {
            throw LoginRefreshError.missingScopes
        }
        guard let executable = Self.findClaudeExecutable() else {
            throw LoginRefreshError.cliNotFound
        }

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
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: LoginRefreshError.failed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
