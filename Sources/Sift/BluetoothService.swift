import Foundation
import IOBluetooth
import SiftCore

enum BluetoothService {
    static func pairedDevices() -> [DeviceItem] {
        guard let raw = IOBluetoothDevice.pairedDevices() else { return [] }
        let devices = raw.compactMap { $0 as? IOBluetoothDevice }
        return devices.compactMap(map(_:))
    }

    static func toggle(deviceID: String, completion: (() -> Void)? = nil) {
        let address = String(deviceID.dropFirst(idPrefix.count))
        guard let device = IOBluetoothDevice(addressString: address) else {
            completion?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if device.isConnected() {
                _ = device.closeConnection()
            } else {
                _ = device.openConnection()
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    static let idPrefix = "bt:"

    private static func map(_ device: IOBluetoothDevice) -> DeviceItem? {
        guard let address = device.addressString, !address.isEmpty else { return nil }
        let name = (device.name?.isEmpty == false ? device.name : device.nameOrAddress) ?? address
        return DeviceItem(
            id: idPrefix + address,
            name: name,
            kind: .bluetooth,
            category: category(for: device),
            isActive: device.isConnected()
        )
    }

    private static func category(for device: IOBluetoothDevice) -> DeviceCategory {
        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor
        switch Int(major) {
        case 0x04:
            switch Int(minor) {
            case 0x01, 0x02: return .headphones
            case 0x05, 0x06: return .speaker
            case 0x0E: return .earbuds
            default: return .audio
            }
        case 0x05:
            if minor & 0x40 != 0 { return .keyboard }
            if minor & 0x80 != 0 { return .mouse }
            return .controller
        case 0x02: return .phone
        case 0x07: return .watch
        default: return .unknown
        }
    }
}
