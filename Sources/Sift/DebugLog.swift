import Foundation

enum DebugLog {
    static let path = "/tmp/sift-debug.log"
    private static let lock = NSLock()
    private static var didReset = false

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        didReset = true
        try? "--- sift start \(Date()) ---\n".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
    }

    static func write(_ msg: String) {
        lock.lock(); defer { lock.unlock() }
        if !didReset {
            didReset = true
            try? "--- sift start \(Date()) ---\n".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
        }
        let line = "\(Date().timeIntervalSinceReferenceDate) \(msg)\n"
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
