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
        #expect(config.panelPosition == .topCenter)
        #expect(config.backdropEnabled == false)
        #expect(config.backdropIntensity == Config.defaultBackdropIntensity)
    }

    @Test func saveThenLoad_roundTrips() {
        let url = tempURL()
        let store = Store(fileURL: url)
        let position = PanelPosition(row: 5, column: 2)
        store.save(Config(
            disabledBundleIDs: ["com.apple.Safari", "com.figma.Desktop"],
            launchAtLogin: true,
            panelPosition: position,
            backdropEnabled: true,
            backdropIntensity: 0.85
        ))

        let reloaded = Store(fileURL: url).load()
        #expect(reloaded.disabledBundleIDs == ["com.apple.Safari", "com.figma.Desktop"])
        #expect(reloaded.launchAtLogin == true)
        #expect(reloaded.panelPosition == position)
        #expect(reloaded.backdropEnabled == true)
        #expect(reloaded.backdropIntensity == 0.85)
    }

    @Test func backdropIntensity_clampsToUnitInterval() {
        let high = Config(backdropIntensity: 5.0)
        let low = Config(backdropIntensity: -1.0)
        #expect(high.backdropIntensity == 1.0)
        #expect(low.backdropIntensity == 0.0)
    }

    @Test func load_legacyFileWithoutPanelPosition_defaultsToTopCenter() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacy = #"{"disabledBundleIDs":["com.apple.Safari"],"launchAtLogin":true}"#
        try legacy.data(using: .utf8)!.write(to: url)

        let config = Store(fileURL: url).load()
        #expect(config.disabledBundleIDs == ["com.apple.Safari"])
        #expect(config.launchAtLogin == true)
        #expect(config.panelPosition == .topCenter)
    }

    @Test func load_legacyEnumPanelPosition_mapsToCorners() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacy = #"{"disabledBundleIDs":[],"launchAtLogin":false,"panelPosition":"bottomRight"}"#
        try legacy.data(using: .utf8)!.write(to: url)

        let last = PanelPosition.gridSize - 1
        let config = Store(fileURL: url).load()
        #expect(config.panelPosition == PanelPosition(row: last, column: last))
    }

    @Test func panelPosition_clampsOutOfRange() {
        let last = PanelPosition.gridSize - 1
        #expect(PanelPosition(row: -1, column: 99) == PanelPosition(row: 0, column: last))
    }

    @Test func interpolatedSteps_pinsCenterAndDistributesEvenly() {
        let steps = PanelPosition.interpolatedSteps(start: 0, center: 60, end: 120)
        #expect(steps.count == PanelPosition.gridSize)
        #expect(steps.first == 0)
        #expect(steps.last == 120)
        #expect(steps[PanelPosition.centerIndex] == 60)
    }
}
