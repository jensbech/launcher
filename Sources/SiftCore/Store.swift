import Foundation
import CoreGraphics

public struct PanelPosition: Codable, Equatable, Hashable, Sendable {
    public static let gridSize = 7

    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = max(0, min(Self.gridSize - 1, row))
        self.column = max(0, min(Self.gridSize - 1, column))
    }

    public static var centerIndex: Int { (gridSize - 1) / 2 }
    public static let topCenter = PanelPosition(row: 0, column: centerIndex)
    public static let center = PanelPosition(row: centerIndex, column: centerIndex)

    public static func interpolatedSteps(start: CGFloat, center: CGFloat, end: CGFloat) -> [CGFloat] {
        let count = gridSize
        let mid = centerIndex
        var result = [CGFloat](repeating: 0, count: count)
        for i in 0..<count {
            if i == mid {
                result[i] = center
            } else if i < mid {
                let t = CGFloat(i) / CGFloat(mid)
                result[i] = start + (center - start) * t
            } else {
                let t = CGFloat(i - mid) / CGFloat(mid)
                result[i] = center + (end - center) * t
            }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case row, column
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let string = try? container.decode(String.self),
           let mapped = PanelPosition.legacyNameMap[string] {
            self = mapped
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let row = try container.decode(Int.self, forKey: .row)
        let column = try container.decode(Int.self, forKey: .column)
        self.init(row: row, column: column)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(column, forKey: .column)
    }

    private static let legacyNameMap: [String: PanelPosition] = {
        let last = gridSize - 1
        let mid = centerIndex
        return [
            "topLeft":      PanelPosition(row: 0, column: 0),
            "topCenter":    PanelPosition(row: 0, column: mid),
            "topRight":     PanelPosition(row: 0, column: last),
            "middleLeft":   PanelPosition(row: mid, column: 0),
            "center":       PanelPosition(row: mid, column: mid),
            "middleRight":  PanelPosition(row: mid, column: last),
            "bottomLeft":   PanelPosition(row: last, column: 0),
            "bottomCenter": PanelPosition(row: last, column: mid),
            "bottomRight":  PanelPosition(row: last, column: last),
        ]
    }()
}

public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let cmdMask: UInt32 = 256
    public static let shiftMask: UInt32 = 512
    public static let optionMask: UInt32 = 2048
    public static let controlMask: UInt32 = 4096

    public static let defaultLauncher = Hotkey(keyCode: 49, modifiers: cmdMask)
    public static let defaultBookmarks = Hotkey(keyCode: 49, modifiers: cmdMask | shiftMask)

    public var hasModifier: Bool {
        modifiers & (Hotkey.cmdMask | Hotkey.shiftMask | Hotkey.optionMask | Hotkey.controlMask) != 0
    }

    public func displayString() -> String {
        modifierGlyphs() + Hotkey.keyName(for: keyCode)
    }

    private func modifierGlyphs() -> String {
        var s = ""
        if modifiers & Hotkey.controlMask != 0 { s += "⌃" }
        if modifiers & Hotkey.optionMask != 0 { s += "⌥" }
        if modifiers & Hotkey.shiftMask != 0 { s += "⇧" }
        if modifiers & Hotkey.cmdMask != 0 { s += "⌘" }
        return s
    }

    public static func keyName(for code: UInt32) -> String {
        if let name = keyNameTable[code] { return name }
        return String(format: "Key %d", code)
    }

    private static let keyNameTable: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
        33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'",
        40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "PgUp",
        117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

public struct Config: Codable, Equatable {
    public var disabledBundleIDs: Set<String>
    public var launchAtLogin: Bool
    public var panelPosition: PanelPosition
    public var backdropEnabled: Bool
    public var backdropIntensity: Double
    public var psychedelicEnabled: Bool
    public var psychedelicIntensity: Double
    public var includeZenBookmarks: Bool
    public var launcherHotkey: Hotkey
    public var bookmarksHotkey: Hotkey
    public var devicesEnabled: Bool
    public var audioSwitcherEnabled: Bool
    public var disabledDeviceIDs: Set<String>

    public static let defaultBackdropIntensity: Double = 0.6
    public static let defaultPsychedelicIntensity: Double = 0.7

    public init(
        disabledBundleIDs: Set<String> = [],
        launchAtLogin: Bool = false,
        panelPosition: PanelPosition = .topCenter,
        backdropEnabled: Bool = false,
        backdropIntensity: Double = Config.defaultBackdropIntensity,
        psychedelicEnabled: Bool = false,
        psychedelicIntensity: Double = Config.defaultPsychedelicIntensity,
        includeZenBookmarks: Bool = true,
        launcherHotkey: Hotkey = .defaultLauncher,
        bookmarksHotkey: Hotkey = .defaultBookmarks,
        devicesEnabled: Bool = false,
        audioSwitcherEnabled: Bool = true,
        disabledDeviceIDs: Set<String> = []
    ) {
        self.disabledBundleIDs = disabledBundleIDs
        self.launchAtLogin = launchAtLogin
        self.panelPosition = panelPosition
        self.backdropEnabled = backdropEnabled
        self.backdropIntensity = max(0, min(1, backdropIntensity))
        self.psychedelicEnabled = psychedelicEnabled
        self.psychedelicIntensity = max(0, min(1, psychedelicIntensity))
        self.includeZenBookmarks = includeZenBookmarks
        self.launcherHotkey = launcherHotkey
        self.bookmarksHotkey = bookmarksHotkey
        self.devicesEnabled = devicesEnabled
        self.audioSwitcherEnabled = audioSwitcherEnabled
        self.disabledDeviceIDs = disabledDeviceIDs
    }

    private enum CodingKeys: String, CodingKey {
        case disabledBundleIDs
        case launchAtLogin
        case panelPosition
        case backdropEnabled
        case backdropIntensity
        case psychedelicEnabled
        case psychedelicIntensity
        case includeZenBookmarks
        case launcherHotkey
        case bookmarksHotkey
        case devicesEnabled
        case audioSwitcherEnabled
        case disabledDeviceIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.disabledBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledBundleIDs) ?? []
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.panelPosition = try container.decodeIfPresent(PanelPosition.self, forKey: .panelPosition) ?? .topCenter
        self.backdropEnabled = try container.decodeIfPresent(Bool.self, forKey: .backdropEnabled) ?? false
        let rawIntensity = try container.decodeIfPresent(Double.self, forKey: .backdropIntensity) ?? Config.defaultBackdropIntensity
        self.backdropIntensity = max(0, min(1, rawIntensity))
        self.psychedelicEnabled = try container.decodeIfPresent(Bool.self, forKey: .psychedelicEnabled) ?? false
        let rawPsych = try container.decodeIfPresent(Double.self, forKey: .psychedelicIntensity) ?? Config.defaultPsychedelicIntensity
        self.psychedelicIntensity = max(0, min(1, rawPsych))
        self.includeZenBookmarks = try container.decodeIfPresent(Bool.self, forKey: .includeZenBookmarks) ?? true
        self.launcherHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .launcherHotkey) ?? .defaultLauncher
        self.bookmarksHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .bookmarksHotkey) ?? .defaultBookmarks
        self.devicesEnabled = try container.decodeIfPresent(Bool.self, forKey: .devicesEnabled) ?? false
        self.audioSwitcherEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioSwitcherEnabled) ?? true
        self.disabledDeviceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledDeviceIDs) ?? []
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
