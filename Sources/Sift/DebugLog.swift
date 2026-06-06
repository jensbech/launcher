import Foundation

enum DebugLog {
    static let path = "/tmp/sift-debug.log"
    private static let lock = NSLock()
    private static var didReset = false
    private static let enabled: Bool = {
        guard let value = ProcessInfo.processInfo.environment["SIFT_DEBUG"] else { return false }
        return !value.isEmpty
    }()

    static func reset() {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        didReset = true
        try? "--- sift start \(Date()) ---\n".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
    }

    static func write(_ msg: @autoclosure () -> String) {
        guard enabled else { return }
        let resolved = msg()
        lock.lock(); defer { lock.unlock() }
        if !didReset {
            didReset = true
            try? "--- sift start \(Date()) ---\n".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
        }
        let line = "\(Date().timeIntervalSinceReferenceDate) \(resolved)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
