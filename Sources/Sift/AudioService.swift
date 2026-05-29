import Foundation
import CoreAudio
import SiftCore

enum AudioService {
    static let idPrefix = "audio:"

    static func outputDevices() -> [DeviceItem] {
        let ids = audioDeviceIDs()
        let defaultID = defaultOutputDeviceID()
        return ids.compactMap { id -> DeviceItem? in
            guard isOutputDevice(id) else { return nil }
            guard let name = deviceName(id) else { return nil }
            return DeviceItem(
                id: idPrefix + String(id),
                name: name,
                kind: .audioOutput,
                category: categorize(name: name),
                isActive: id == defaultID
            )
        }
    }

    static func setActive(deviceID: String) {
        let raw = String(deviceID.dropFirst(idPrefix.count))
        guard var id = AudioDeviceID(raw) else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
    }

    private static func audioDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size
        )
        guard sizeStatus == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &ids
        )
        guard status == noErr else { return [] }
        return ids
    }

    private static func isOutputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        guard status == noErr, let n = name?.takeRetainedValue() else { return nil }
        return n as String
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &id
        )
        return id
    }

    private static func categorize(name: String) -> DeviceCategory {
        let lower = name.lowercased()
        if lower.contains("airpods") || lower.contains("buds") { return .earbuds }
        if lower.contains("headphone") || lower.contains("beats") { return .headphones }
        if lower.contains("speaker") || lower.contains("homepod") { return .speaker }
        return .audio
    }
}
