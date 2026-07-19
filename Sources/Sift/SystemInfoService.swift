import Foundation
import IOKit
import IOKit.ps

@MainActor
final class SystemInfoService {
    static let shared = SystemInfoService()

    private static let ttl: TimeInterval = 30

    private var cachedBattery: BatteryHealth?
    private var cachedBatteryAt: Date?

    private var cachedStorage: Storage?
    private var cachedStorageAt: Date?

    struct BatteryHealth: Equatable {
        let percent: Int
        let cycleCount: Int?
    }

    struct Storage: Equatable {
        let totalBytes: Int64
        let freeBytes: Int64
    }

    private init() {}

    func batteryHealth() -> BatteryHealth? {
        if let cached = cachedBattery, let at = cachedBatteryAt, Date().timeIntervalSince(at) < Self.ttl {
            return cached
        }
        let result = Self.readBatteryHealth()
        cachedBattery = result
        cachedBatteryAt = Date()
        return result
    }

    func storage() -> Storage? {
        if let cached = cachedStorage, let at = cachedStorageAt, Date().timeIntervalSince(at) < Self.ttl {
            return cached
        }
        let result = Self.readStorage()
        cachedStorage = result
        cachedStorageAt = Date()
        return result
    }

    private static func readBatteryHealth() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let maxCap = IORegistryEntryCreateCFProperty(service, "AppleRawMaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            ?? IORegistryEntryCreateCFProperty(service, "MaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        let designCap = IORegistryEntryCreateCFProperty(service, "DesignCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        let cycles = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int

        guard let maxCap, let designCap, designCap > 0 else { return nil }
        let percent = Int((Double(maxCap) / Double(designCap) * 100).rounded())
        return BatteryHealth(percent: percent, cycleCount: cycles)
    }

    private static func readStorage() -> Storage? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]),
        let total = values.volumeTotalCapacity else { return nil }
        let available: Int64
        if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
            available = importantUsage
        } else if let fallback = values.volumeAvailableCapacity {
            available = Int64(fallback)
        } else {
            available = 0
        }
        return Storage(totalBytes: Int64(total), freeBytes: available)
    }
}

extension SystemInfoService.Storage {
    var freeFormatted: String { Self.format(freeBytes) }
    var totalFormatted: String { Self.format(totalBytes) }

    private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

enum SystemInfoCommand: Hashable, Identifiable {
    case batteryHealth
    case storage

    var id: String {
        switch self {
        case .batteryHealth: return "sysinfo:battery"
        case .storage: return "sysinfo:storage"
        }
    }

    var name: String {
        switch self {
        case .batteryHealth: return "Battery health"
        case .storage: return "Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .batteryHealth: return "battery.75"
        case .storage: return "internaldrive"
        }
    }

    @MainActor
    var trailingValue: String? {
        switch self {
        case .batteryHealth:
            guard let h = SystemInfoService.shared.batteryHealth() else { return nil }
            if let cycles = h.cycleCount {
                return "\(h.percent)% · \(cycles) cycles"
            }
            return "\(h.percent)%"
        case .storage:
            guard let s = SystemInfoService.shared.storage() else { return nil }
            return "\(s.freeFormatted) free of \(s.totalFormatted)"
        }
    }

    @MainActor
    static func available() -> [SystemInfoCommand] {
        var commands: [SystemInfoCommand] = []
        if SystemInfoService.shared.batteryHealth() != nil {
            commands.append(.batteryHealth)
        }
        commands.append(.storage)
        return commands
    }
}
