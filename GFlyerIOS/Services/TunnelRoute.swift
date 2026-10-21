import Darwin

/// 查本機通道有沒有開：送往目標 IP 的封包會不會走 VPN 介面。
///
/// 本機通道只把目標 IP 這一條路由導進 VPN 介面，其他流量照舊走 Wi-Fi 或
/// 行動網絡，所以「這一條路由走 VPN 介面」就代表通道已連線。
enum TunnelRoute {
    /// 問系統：送往 `deviceIP` 的封包會從哪張網卡出去。
    ///
    /// UDP 的 `connect()` 只查路由表、不送出任何封包，所以這個檢查沒有副作用，
    /// 也不會觸發 VPN 的隨選連線規則（那些規則比對的是網域名稱）。
    static func routesThroughTunnel(deviceIP: String) -> Bool {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(49_152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let connected = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        // 飛行模式且沒有 VPN 時沒有任何路由，connect 會直接失敗
        guard connected == 0 else { return false }

        var source = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0, let name = interfaceName(owning: source.sin_addr) else { return false }
        return isTunnelInterface(name)
    }

    /// iOS 的 VPN 介面名稱：Network Extension 用 `utun`，IKEv2/IPsec 用 `ipsec`。
    static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
    }

    private static func interfaceName(owning address: in_addr) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let raw = entry.pointee.ifa_addr,
                  raw.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let candidate = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            if candidate.s_addr == address.s_addr {
                return String(cString: entry.pointee.ifa_name)
            }
        }
        return nil
    }
}
