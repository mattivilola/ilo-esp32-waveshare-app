import Darwin
import Foundation

enum LocalIPv4Address {
    static func current() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var candidate: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &name,
                socklen_t(name.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            let value = String(decoding: name.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
            let interfaceName = String(cString: interface.ifa_name)
            if interfaceName == "en0" { return value }
            candidate = candidate ?? value
        }
        return candidate
    }
}
