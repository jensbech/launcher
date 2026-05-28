import Foundation

public struct Config: Codable, Equatable {
    public var disabledBundleIDs: Set<String>
    public var launchAtLogin: Bool

    public init(disabledBundleIDs: Set<String> = [], launchAtLogin: Bool = false) {
        self.disabledBundleIDs = disabledBundleIDs
        self.launchAtLogin = launchAtLogin
    }
}

public final class Store {
    public let fileURL: URL

    public init(fileURL: URL = Store.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sift/config.json")
    }

    public func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    public func save(_ config: Config) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: fileURL)
    }
}
