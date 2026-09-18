import Foundation

enum AppLogger {
    private static let queue = DispatchQueue(label: "com.tugkanboz.claudehub.logger")

    static func write(_ message: String) {
        queue.async {
            let manager = FileManager.default
            let base = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let directory = base.appendingPathComponent("Logs/ClaudeHub", isDirectory: true)
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("menubar.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(timestamp) \(message)\n".utf8)
            if manager.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}
