import Foundation
import IOKit
import IOKit.serial

public struct USBBoardDevice: Equatable, Sendable {
    public let path: String
    public let serialNumber: String?
    public let vendorID: UInt16
    public let productID: UInt16

    public init(path: String, serialNumber: String?, vendorID: UInt16, productID: UInt16) {
        self.path = path
        self.serialNumber = serialNumber.flatMap(HostConfiguration.normalizedUSBSerialNumber)
        self.vendorID = vendorID
        self.productID = productID
    }

    public var isEspressifUSBSerialJTAG: Bool {
        vendorID == 0x303A && productID == 0x1001
    }
}

public enum USBBoardPresence: Equatable, Sendable {
    case disconnected
    case compatible(path: String)
    case paired(path: String)

    public var isConnected: Bool {
        self != .disconnected
    }

    public var path: String? {
        switch self {
        case .disconnected: nil
        case let .compatible(path), let .paired(path): path
        }
    }

    public var displayText: String {
        switch self {
        case .disconnected: "Not connected"
        case .compatible: "Compatible ESP32-S3 attached"
        case .paired: "Paired board attached"
        }
    }
}

public protocol USBBoardDiscovering: Sendable {
    func connectedDevices() -> [USBBoardDevice]
}

public enum USBBoardMatcher {
    public static func presence(
        devices: [USBBoardDevice],
        configuredSerialNumber: String?
    ) -> USBBoardPresence {
        let compatible = devices.filter(\.isEspressifUSBSerialJTAG)
        guard !compatible.isEmpty else { return .disconnected }
        if let expected = configuredSerialNumber.flatMap(HostConfiguration.normalizedUSBSerialNumber),
           let paired = compatible.first(where: { $0.serialNumber == expected }) {
            return .paired(path: paired.path)
        }
        return .compatible(path: compatible[0].path)
    }
}

public struct IOKitUSBBoardDiscovery: USBBoardDiscovering {
    public init() {}

    public func connectedDevices() -> [USBBoardDevice] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        (matching as NSMutableDictionary)[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [USBBoardDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let path = stringProperty(kIOCalloutDeviceKey, from: service),
                  let vendorID = numberProperty("idVendor", from: service),
                  let productID = numberProperty("idProduct", from: service),
                  UInt16(exactly: vendorID) != nil,
                  UInt16(exactly: productID) != nil
            else { continue }
            devices.append(USBBoardDevice(
                path: path,
                serialNumber: stringProperty("USB Serial Number", from: service)
                    ?? stringProperty("kUSBSerialNumberString", from: service),
                vendorID: UInt16(vendorID),
                productID: UInt16(productID)
            ))
        }
        return devices.sorted { $0.path < $1.path }
    }

    private func property(_ key: String, from service: io_object_t) -> CFTypeRef? {
        return IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
    }

    private func stringProperty(_ key: String, from service: io_object_t) -> String? {
        property(key, from: service) as? String
    }

    private func numberProperty(_ key: String, from service: io_object_t) -> Int? {
        (property(key, from: service) as? NSNumber)?.intValue
    }
}
