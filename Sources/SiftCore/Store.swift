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

public struct Config: Codable, Equatable {
    public var disabledBundleIDs: Set<String>
    public var launchAtLogin: Bool
    public var panelPosition: PanelPosition
    public var backdropEnabled: Bool
    public var backdropIntensity: Double

    public static let defaultBackdropIntensity: Double = 0.6

    public init(
        disabledBundleIDs: Set<String> = [],
        launchAtLogin: Bool = false,
        panelPosition: PanelPosition = .topCenter,
        backdropEnabled: Bool = false,
        backdropIntensity: Double = Config.defaultBackdropIntensity
    ) {
        self.disabledBundleIDs = disabledBundleIDs
        self.launchAtLogin = launchAtLogin
        self.panelPosition = panelPosition
        self.backdropEnabled = backdropEnabled
        self.backdropIntensity = max(0, min(1, backdropIntensity))
    }

    private enum CodingKeys: String, CodingKey {
        case disabledBundleIDs
        case launchAtLogin
        case panelPosition
        case backdropEnabled
        case backdropIntensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.disabledBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledBundleIDs) ?? []
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.panelPosition = try container.decodeIfPresent(PanelPosition.self, forKey: .panelPosition) ?? .topCenter
        self.backdropEnabled = try container.decodeIfPresent(Bool.self, forKey: .backdropEnabled) ?? false
        let rawIntensity = try container.decodeIfPresent(Double.self, forKey: .backdropIntensity) ?? Config.defaultBackdropIntensity
        self.backdropIntensity = max(0, min(1, rawIntensity))
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
