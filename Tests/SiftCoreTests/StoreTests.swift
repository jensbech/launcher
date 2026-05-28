import Foundation
import Testing
@testable import SiftCore

struct StoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    @Test func load_missingFile_returnsDefaultWithNothingDisabled() {
        let store = Store(fileURL: tempURL())
        let config = store.load()
        #expect(config.disabledBundleIDs == [])
        #expect(config.launchAtLogin == false)
    }

    @Test func saveThenLoad_roundTrips() {
        let url = tempURL()
        let store = Store(fileURL: url)
        store.save(Config(disabledBundleIDs: ["com.apple.Safari", "com.figma.Desktop"], launchAtLogin: true))

        let reloaded = Store(fileURL: url).load()
        #expect(reloaded.disabledBundleIDs == ["com.apple.Safari", "com.figma.Desktop"])
        #expect(reloaded.launchAtLogin == true)
    }
}
