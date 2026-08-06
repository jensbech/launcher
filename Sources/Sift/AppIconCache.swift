import AppKit
import Foundation

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 512
    }

    func icon(forPath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func evict(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    private var warmTask: Task<Void, Never>?

    func warm(paths: [String]) {
        warmTask?.cancel()
        warmTask = Task { @MainActor [weak self] in
            for path in paths {
                if Task.isCancelled { return }
                guard let self else { return }
                if self.cache.object(forKey: path as NSString) == nil {
                    _ = self.icon(forPath: path)
                }
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
        }
    }
}
