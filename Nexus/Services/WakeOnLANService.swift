import Foundation

/// Sends a Wake-on-LAN "magic packet" (6×0xFF followed by the target MAC repeated
/// 16×) as a UDP broadcast. Pure POSIX socket with SO_BROADCAST — no external tool.
enum WakeOnLANService {

    enum Result {
        case sent
        case invalidMAC
        case failed
    }

    static func wake(mac: String, port: UInt16 = 9) -> Result {
        let octets = mac.split(whereSeparator: { ":-".contains($0) }).compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return .invalidMAC }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: octets) }

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return .failed }
        defer { close(fd) }

        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = in_addr_t(0xFFFF_FFFF)   // 255.255.255.255

        let sent = packet.withUnsafeBytes { buf -> Int in
            withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                    sendto(fd, buf.baseAddress, buf.count, 0, saptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count ? .sent : .failed
    }
}
