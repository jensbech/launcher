import Foundation
import Testing
@testable import SiftCore

final class AppIndexTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(named name: String, bundleID: String, in dir: URL, displayName: String? = nil) throws {
        let appDir = dir.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
        if let displayName {
            plist["CFBundleDisplayName"] = displayName
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: appDir.appendingPathComponent("Info.plist"))
    }

    @Test func scan_findsApps() throws {
        try makeApp(named: "Safari", bundleID: "com.apple.Safari", in: root)
        try makeApp(named: "Mail", bundleID: "com.apple.Mail", in: root)

        let items = AppIndex.scan(directories: [root])
        #expect(items.map(\.name) == ["Mail", "Safari"])
        #expect(Set(items.map(\.id)) == ["com.apple.Safari", "com.apple.Mail"])
    }

    @Test func scan_dedupesByBundleID() throws {
        let dirA = root.appendingPathComponent("A")
        let dirB = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try makeApp(named: "Safari", bundleID: "com.apple.Safari", in: dirA)
        try makeApp(named: "Safari", bundleID: "com.apple.Safari", in: dirB)

        let items = AppIndex.scan(directories: [dirA, dirB])
        #expect(items.count == 1)
    }

    @Test func scan_ignoresMissingDirectories() {
        let items = AppIndex.scan(directories: [root.appendingPathComponent("nope")])
        #expect(items == [])
    }

    @Test func scan_acceptsDirectAppBundlePaths() throws {
        try makeApp(named: "Safari", bundleID: "com.apple.Safari", in: root)
        let bundle = root.appendingPathComponent("Safari.app")
        let items = AppIndex.scan(directories: [bundle])
        #expect(items.map(\.id) == ["com.apple.Safari"])
    }

    @Test func defaultSearchPaths_includeFinder() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
        #expect(AppIndex.defaultSearchPaths.contains(finder))
    }

    @Test func makeItem_prefersDisplayNameOverBundleName() throws {
        try makeApp(named: "Bundle Name", bundleID: "com.example.test", in: root, displayName: "Display Name")
        let items = AppIndex.scan(directories: [root])
        #expect(items.first?.name == "Display Name")
    }
}
