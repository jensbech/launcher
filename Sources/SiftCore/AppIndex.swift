import Foundation

public struct AppIndex {
    public static let defaultSearchPaths: [URL] = {
        var paths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent("Applications", isDirectory: true))
        paths.append(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true))
        return paths
    }()

    public static func scan(directories: [URL], fileManager: FileManager = .default) -> [AppItem] {
        var seen = Set<String>()
        var items: [AppItem] = []
        for dir in directories {
            if dir.pathExtension == "app" {
                guard let item = makeItem(at: dir) else { continue }
                if seen.insert(item.id).inserted {
                    items.append(item)
                }
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                guard let item = makeItem(at: entry) else { continue }
                if seen.insert(item.id).inserted {
                    items.append(item)
                }
            }
        }
        return items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func makeItem(at url: URL) -> AppItem? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary
        guard let id = bundle.bundleIdentifier ?? info?["CFBundleIdentifier"] as? String else {
            return nil
        }
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppItem(id: id, name: name, path: url.path)
    }
}
