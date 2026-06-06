import AppKit
import CryptoKit
import Foundation

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let diskQueue = DispatchQueue(label: "sift.appiconcache.disk", qos: .utility)
    private let diskCacheDir: URL?

    init() {
        self.diskCacheDir = Self.makeCacheDir()
        cache.countLimit = 512
    }

    func icon(forPath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        scheduleDiskWrite(image: icon, path: path)
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

    private func scheduleDiskWrite(image: NSImage, path: String) {
        guard let dir = diskCacheDir else { return }
        let fileURL = dir.appendingPathComponent(Self.cacheKey(forPath: path)).appendingPathExtension("png")
        diskQueue.async { [image] in
            autoreleasepool {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:])
                else { return }
                try? png.write(to: fileURL, options: .atomic)
            }
        }
    }

    private static func makeCacheDir() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Sift", isDirectory: true).appendingPathComponent("icons", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir
    }

    private static func cacheKey(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
