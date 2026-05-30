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
                category: categorize(id: id, name: name),
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
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else {
            return false
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        )
        for buffer in bufferList where buffer.mNumberChannels > 0 {
            return true
        }
        return false
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

    private static func categorize(id: AudioDeviceID, name: String) -> DeviceCategory {
        let transport = transportType(id)
        if transport == kAudioDeviceTransportTypeAirPlay { return .airplay }
        if transport == kAudioDeviceTransportTypeBuiltIn { return .builtIn }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            let lower = name.lowercased()
            if lower.contains("airpod") || lower.contains("buds") { return .earbuds }
            return .headphones
        }
        let lower = name.lowercased()
        if lower.contains("airpod") || lower.contains("buds") { return .earbuds }
        if lower.contains("headphone") || lower.contains("beats") { return .headphones }
        if lower.contains("homepod") || lower.contains("speaker") { return .speaker }
        return .audio
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }
}
