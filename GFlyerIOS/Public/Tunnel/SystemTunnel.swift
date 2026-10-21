import NetworkExtension

/// `LocalTunnel` 經它開關 iOS 的 VPN 設定；測試換成假的。
@MainActor
protocol TunnelSystem: AnyObject {
    /// 建立或更新 GFlyer 的通道設定並開啟通道。第一次建立時 iOS 會問使用者可否加入 VPN 設定，
    /// 使用者回答之後才返回。
    func connect(targetAddress: String) async throws
    /// 關閉通道；沒有設定或已經關了就甚麼都不做。
    func disconnect() async
}

/// 用 `NETunnelProviderManager` 開關 App 內建的通道 extension（`GFlyerPublicTunnel`，bundle id
/// 是 App 的加上 `.tunnel`）。iOS 的 VPN 設定裏只有一個 GFlyer 的設定，目標 IP 寫在它的
/// `providerConfiguration`（`PacketReflector.targetAddressKey`）。
@MainActor
final class SystemTunnel: TunnelSystem {
    private let providerBundleIdentifier: String
    private let stopTimeoutNanoseconds: UInt64

    init(
        providerBundleIdentifier: String = (Bundle.main.bundleIdentifier ?? "") + ".tunnel",
        stopTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.stopTimeoutNanoseconds = stopTimeoutNanoseconds
    }

    func connect(targetAddress: String) async throws {
        let manager = try await existingManager() ?? NETunnelProviderManager()
        let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol ?? NETunnelProviderProtocol()
        let changed = !manager.isEnabled
            || configuration.providerBundleIdentifier != providerBundleIdentifier
            || configuration.providerConfiguration?[PacketReflector.targetAddressKey] as? String != targetAddress
        if changed {
            configuration.providerBundleIdentifier = providerBundleIdentifier
            configuration.serverAddress = targetAddress
            configuration.providerConfiguration = [PacketReflector.targetAddressKey: targetAddress]
            manager.protocolConfiguration = configuration
            manager.localizedDescription = "GFlyer 本機通道"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            // Apple 的文件：存了之後要重新載入，才開得了剛存的設定
            try await manager.loadFromPreferences()
            // 目標 IP 改了：開着的通道還在用舊的，先關掉再開
            if manager.connection.status != .disconnected, manager.connection.status != .invalid {
                manager.connection.stopVPNTunnel()
                await waitUntilStopped(manager.connection)
            }
        }
        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            return
        default:
            try manager.connection.startVPNTunnel()
        }
    }

    func disconnect() async {
        guard let manager = try? await existingManager() else { return }
        manager.connection.stopVPNTunnel()
    }

    private func existingManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == providerBundleIdentifier
        } ?? managers.first
    }

    private func waitUntilStopped(_ connection: NEVPNConnection) async {
        let interval: UInt64 = 200_000_000
        var waited: UInt64 = 0
        while connection.status != .disconnected, connection.status != .invalid, waited < stopTimeoutNanoseconds {
            try? await Task.sleep(nanoseconds: interval)
            waited += interval
        }
    }
}
