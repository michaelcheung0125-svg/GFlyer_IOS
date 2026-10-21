import NetworkExtension

/// 公開版的本機通道 extension（docs/APP_STORE_PLAN.md 第 12 項）。只把目標 IP 這一個位址的路由
/// 導進來，把封包對調位址後送回 iPhone 自己（`PacketReflector`）；其他網絡流量不經過這裏，
/// 也沒有 DNS 設定。目標 IP 由 App 寫在通道設定的 `providerConfiguration`，從 iOS 的 VPN 設定
/// 直接開啟時也讀得到。
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(
        options _: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let configuration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let target = configuration?[PacketReflector.targetAddressKey] as? String,
              let reflector = PacketReflector(targetAddress: target) else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        let host = "255.255.255.255"
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: reflector.interfaceAddress)
        let ipv4 = NEIPv4Settings(addresses: [reflector.interfaceAddress], subnetMasks: [host])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: target, subnetMask: host)]
        settings.ipv4Settings = ipv4
        setTunnelNetworkSettings(settings) { [weak self] error in
            if error == nil {
                self?.reflectPackets(with: reflector)
            }
            completionHandler(error)
        }
    }

    override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    /// 讀一批封包，對調後寫回去，再讀下一批。通道關掉之後 iOS 不再回呼，迴圈自己結束。
    private func reflectPackets(with reflector: PacketReflector) {
        packetFlow.readPackets { [weak self] packets, families in
            guard let self else { return }
            var replies: [Data] = []
            var replyFamilies: [NSNumber] = []
            for (packet, family) in zip(packets, families) {
                guard let reply = reflector.reflect(packet) else { continue }
                replies.append(reply)
                replyFamilies.append(family)
            }
            if !replies.isEmpty {
                packetFlow.writePackets(replies, withProtocols: replyFamilies)
            }
            reflectPackets(with: reflector)
        }
    }
}
