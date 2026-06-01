import AppKit
import Foundation
import Combine
import SiftCore

@MainActor
final class FaviconCache: ObservableObject {
    static let shared = FaviconCache()

    @Published private(set) var icons: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private let cacheDir: URL
    private let session: URLSession
    private var pendingHosts: Set<String> = []
    private var pendingQueue: [String] = []
    private var activeFetches = 0
    private let maxConcurrent = 6

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("Sift/favicons")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil
        session = URLSession(configuration: config)

        loadDiskCache()
        if icons[Self.swaggerKey] == nil, let embedded = Self.embeddedSwaggerIcon() {
            icons[Self.swaggerKey] = embedded
            persist(image: embedded, host: Self.swaggerKey)
        }
    }

    private static func embeddedSwaggerIcon() -> NSImage? {
        guard let data = Data(base64Encoded: embeddedSwaggerBase64) else { return nil }
        return NSImage(data: data)
    }

    private static let embeddedSwaggerBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAkFBMVEUAAAAQM0QWNUYWNkYXNkYALjoWNUYYOEUXN0YaPEUPMUAUM0QVNUYWNkYWNUYWNUUWNUYVNEYWNkYWNUYWM0eF6i0XNkchR0OB5SwzZj9wyTEvXkA3az5apTZ+4C5DgDt31C9frjU5bz5uxTI/eDxzzjAmT0IsWUEeQkVltzR62S6D6CxIhzpKijpJiDpOkDl4b43lAAAAFXRSTlMAFc304QeZ/vj+ECB3xKlGilPXvS2Ka/h0AAABfklEQVR42oVT2XaCMBAdJRAi7pYJa2QHxbb//3ctSSAUPfa+THLmzj4DBvZpvyauS9b7kw3PWDkWsrD6fFQhQ9dZLfVbC5M88CWCPERr+8fLZodJ5M8QJbjbGL1H2M1fIGfEm+wJN+bGCSc6EXtNS/8FSrq2VX6YDv++XLpJ8SgDWMnwqznGo6alcTbIxB2CHKn8VFikk2mMV2lEnV+CJd9+jJlxXmMr5dW14YCqwgbFpO8FNvJxwwM4TPWPo5QalEsRMAcusXpi58/QUEWPL0AK1ThM5oQCUyXPoPINkdd922VBw4XgTV9zDGWWFrgjIQs4vwvOg6xr+6gbCTqE+DYhlMGX0CF2OknK5gQ2JrkDh/W6TOEbYDeVecKbJtyNXiCfGmW7V93J2hDus1bDfhxWbIZVYDXITA7Lo6E0Ktgg9eB4KWuR44aj7ppBVPazhQH7/M/KgWe9X1qAg8XypT6nxIMJH+T94QCsLvj29IYwZxyO9/F8vCbO9tX5/wDGjEZ7vrgFZwAAAABJRU5ErkJggg=="

    private static let swaggerKey = "_swagger_"

    private static func isSwagger(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains("/swagger/") || lower.hasSuffix("/swagger")
    }

    func icon(for urlString: String) -> NSImage? {
        if Self.isSwagger(urlString), let img = icons[Self.swaggerKey] {
            return img
        }
        guard let host = URL(string: urlString)?.host else { return nil }
        return icons[host]
    }

    func requestIcon(for urlString: String) {
        if Self.isSwagger(urlString) {
            enqueue(host: Self.swaggerKey, scheme: "https")
        }
        guard let parsed = URL(string: urlString), let host = parsed.host else { return }
        enqueue(host: host, scheme: parsed.scheme ?? "https")
    }

    func prefetch(bookmarks: [Bookmark]) {
        var seen = Set<String>()
        var sawSwagger = false
        for bookmark in bookmarks {
            if !sawSwagger, Self.isSwagger(bookmark.url) {
                sawSwagger = true
                enqueue(host: Self.swaggerKey, scheme: "https")
            }
            guard let parsed = URL(string: bookmark.url), let host = parsed.host else { continue }
            if seen.insert(host).inserted {
                enqueue(host: host, scheme: parsed.scheme ?? "https")
            }
        }
    }

    private func enqueue(host: String, scheme: String) {
        if icons[host] != nil { return }
        if inFlight.contains(host) || failed.contains(host) { return }
        if pendingHosts.contains(host) { return }
        pendingHosts.insert(host)
        pendingQueue.append("\(scheme)|\(host)")
        pumpQueue()
    }

    private func pumpQueue() {
        while activeFetches < maxConcurrent, !pendingQueue.isEmpty {
            let entry = pendingQueue.removeFirst()
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let scheme = parts[0]
            let host = parts[1]
            pendingHosts.remove(host)
            if icons[host] != nil { continue }
            if inFlight.contains(host) || failed.contains(host) { continue }
            inFlight.insert(host)
            activeFetches += 1
            startFetch(host: host, scheme: scheme)
        }
    }

    private func startFetch(host: String, scheme: String) {
        let session = self.session
        Task.detached(priority: .utility) {
            let image = await Self.fetchIcon(host: host, scheme: scheme, session: session)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(host)
                self.activeFetches -= 1
                if let image {
                    self.icons[host] = image
                    self.persist(image: image, host: host)
                } else {
                    self.failed.insert(host)
                }
                self.pumpQueue()
            }
        }
    }

    private static func fetchIcon(host: String, scheme: String, session: URLSession) async -> NSImage? {
        let candidates: [String]
        if host == swaggerKey {
            candidates = [
                "https://raw.githubusercontent.com/swagger-api/swagger-ui/master/dist/favicon-32x32.png",
                "https://editor.swagger.io/favicon-32x32.png"
            ]
        } else {
            candidates = [
                "\(scheme)://\(host)/favicon.ico",
                "https://\(host)/favicon.ico",
                "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://\(host)&size=64",
                "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
            ]
        }
        var seen = Set<String>()
        for raw in candidates where seen.insert(raw).inserted {
            guard let url = URL(string: raw) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            do {
                let (data, _) = try await session.data(for: req)
                guard !data.isEmpty else { continue }
                if let image = NSImage(data: data), image.size.width > 1, image.size.height > 1 {
                    return image
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func loadDiskCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let host = file.deletingPathExtension().lastPathComponent
            if let image = NSImage(contentsOf: file), image.size.width > 1 {
                icons[host] = image
            }
        }
    }

    private func persist(image: NSImage, host: String) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let safe = host.replacingOccurrences(of: "/", with: "_")
        let url = cacheDir.appendingPathComponent("\(safe).png")
        try? png.write(to: url)
    }
}
