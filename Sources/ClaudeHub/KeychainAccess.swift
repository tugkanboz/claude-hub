import Foundation
import Security

enum KeychainInteraction {
    case background
    case userInitiated
}

enum KeychainAccess {
    private static let lock = NSLock()

    static func perform(_ interaction: KeychainInteraction, operation: () -> OSStatus) -> OSStatus {
        // Claude Code uses the legacy macOS keychain. Its UI setting is process-wide.
        lock.lock()
        defer { lock.unlock() }
        var previous: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else { return readStatus }
        let status = SecKeychainSetUserInteractionAllowed(interaction == .userInitiated)
        guard status == errSecSuccess else { return status }
        defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return operation()
    }
}
