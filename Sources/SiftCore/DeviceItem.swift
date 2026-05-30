import Foundation

public enum DeviceKind: String, Codable, Sendable, Hashable {
    case bluetooth
    case audioOutput
}

public enum DeviceCategory: String, Codable, Sendable, Hashable {
    case headphones, speaker, earbuds, watch, mouse, keyboard, phone, controller
    case audio, airplay, builtIn, unknown

    public var systemImageName: String {
        switch self {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .earbuds: return "earbuds"
        case .watch: return "applewatch"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .phone: return "iphone"
        case .controller: return "gamecontroller"
        case .audio: return "speaker.wave.2.fill"
        case .airplay: return "airplayaudio"
        case .builtIn: return "laptopcomputer"
        case .unknown: return "dot.radiowaves.right"
        }
    }
}

public struct DeviceItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let kind: DeviceKind
    public let category: DeviceCategory
    public let isActive: Bool

    public init(id: String, name: String, kind: DeviceKind, category: DeviceCategory, isActive: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.isActive = isActive
    }

    public var actionLabel: String {
        switch kind {
        case .bluetooth: return isActive ? "Disconnect" : "Connect"
        case .audioOutput: return isActive ? "Active output" : "Switch output"
        }
    }
}
