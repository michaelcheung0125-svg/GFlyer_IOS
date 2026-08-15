import Foundation

#if GFLYER_IDEVICE
import Darwin
import idevice

actor IdeviceLocationSimulationBackend: LocationSimulationBackend {
    nonisolated let name = "idevice 裝置定位"
    nonisolated let canControlDeviceLocation = true
    private let remotePairingPort: UInt16 = 49_152

    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var locationSimulation: OpaquePointer?

    func testConnection(pairingFileURL: URL, deviceIP: String) async throws {
        if locationSimulation != nil { return }
        do {
            try await ensureSession(pairingFileURL: pairingFileURL, deviceIP: deviceIP)
            cleanup()
        } catch {
            cleanup()
            throw error
        }
    }

    func setLocation(_ coordinate: GeoCoordinate, pairingFileURL: URL, deviceIP: String) async throws {
        try await ensureSession(pairingFileURL: pairingFileURL, deviceIP: deviceIP)
        guard let locationSimulation else {
            throw SimulationError.connectionFailed("定位模擬服務未建立有效連線。")
        }

        do {
            try check(
                location_simulation_set(locationSimulation, coordinate.latitude, coordinate.longitude),
                fallback: "無法更新模擬位置。"
            )
        } catch {
            cleanup()
            throw error
        }
    }

    func clearLocation(pairingFileURL: URL, deviceIP: String) async throws {
        try await ensureSession(pairingFileURL: pairingFileURL, deviceIP: deviceIP)
        guard let locationSimulation else {
            throw SimulationError.connectionFailed("定位模擬服務未建立有效連線。")
        }
        let error = location_simulation_clear(locationSimulation)
        cleanup()
        try check(error, fallback: "無法清除模擬位置。")
    }

    private func ensureSession(pairingFileURL: URL, deviceIP: String) async throws {
        if locationSimulation != nil { return }

        guard var address = IPv4SocketAddress(ip: deviceIP, port: remotePairingPort) else {
            throw SimulationError.invalidAddress
        }

        var pairingFile: OpaquePointer?
        try check(
            pairingFileURL.path.withCString { rp_pairing_file_read($0, &pairingFile) },
            fallback: "無法讀取 pairing file。"
        )
        guard let pairingFile else { throw SimulationError.pairingFileRequired }
        defer { rp_pairing_file_free(pairingFile) }

        let tunnelError = withUnsafePointer(to: &address.value) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "GFlyerLocation",
                    pairingFile,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        do {
            try check(tunnelError, fallback: "無法建立 LocalDevVPN/CoreDevice 通道。")
            try await connectRemoteServer()
            try check(
                location_simulation_new(remoteServer, &locationSimulation),
                fallback: "無法啟動 iOS 定位模擬服務。"
            )

            remoteServer = nil
        } catch {
            cleanup()
            throw error
        }
    }

    private func connectRemoteServer() async throws {
        let initialError = remote_server_connect_rsd(adapter, handshake, &remoteServer)
        if initialError == nil { return }
        idevice_error_free(initialError)

        let files = try await DeveloperDiskImageStore.shared.prepare()
        try mountDeveloperDiskImage(files)
        try check(
            remote_server_connect_rsd(adapter, handshake, &remoteServer),
            fallback: "DDI 已掛載，但仍無法連接 RemoteXPC 服務。"
        )
    }

    private func mountDeveloperDiskImage(_ files: DeveloperDiskImageFiles) throws {
        var lockdownClient: OpaquePointer?
        try check(
            lockdownd_connect_rsd(adapter, handshake, &lockdownClient),
            fallback: "無法連接 lockdownd 以準備 DDI。"
        )
        guard let lockdownClient else {
            throw SimulationError.developerDiskImage("lockdownd 未建立有效連線。")
        }
        defer { lockdownd_client_free(lockdownClient) }

        var uniqueChipIDPlist: plist_t?
        try check(
            lockdownd_get_value(lockdownClient, "UniqueChipID", nil, &uniqueChipIDPlist),
            fallback: "無法讀取 UniqueChipID。"
        )
        guard let uniqueChipIDPlist else {
            throw SimulationError.developerDiskImage("裝置沒有傳回 UniqueChipID。")
        }
        defer { plist_free(uniqueChipIDPlist) }

        var uniqueChipID: UInt64 = 0
        plist_get_uint_val(uniqueChipIDPlist, &uniqueChipID)
        guard uniqueChipID != 0 else {
            throw SimulationError.developerDiskImage("UniqueChipID 無效。")
        }

        var imageMounter: OpaquePointer?
        try check(
            image_mounter_connect_rsd(adapter, handshake, &imageMounter),
            fallback: "無法連接 Personalized DDI 服務。"
        )
        guard let imageMounter else {
            throw SimulationError.developerDiskImage("DDI mounter 未建立有效連線。")
        }
        defer { image_mounter_free(imageMounter) }

        let image = try Data(contentsOf: files.image, options: .mappedIfSafe)
        let trustCache = try Data(contentsOf: files.trustCache, options: .mappedIfSafe)
        let buildManifest = try Data(contentsOf: files.buildManifest, options: .mappedIfSafe)

        let error = image.withUnsafeBytes { imageBuffer in
            trustCache.withUnsafeBytes { trustCacheBuffer in
                buildManifest.withUnsafeBytes { manifestBuffer in
                    image_mounter_mount_personalized_with_callback_rsd(
                        imageMounter,
                        adapter,
                        handshake,
                        imageBuffer.bindMemory(to: UInt8.self).baseAddress,
                        image.count,
                        trustCacheBuffer.bindMemory(to: UInt8.self).baseAddress,
                        trustCache.count,
                        manifestBuffer.bindMemory(to: UInt8.self).baseAddress,
                        buildManifest.count,
                        nil,
                        uniqueChipID,
                        developerDiskImageProgress,
                        nil
                    )
                }
            }
        }
        try check(error, fallback: "無法掛載 Personalized DDI。")
    }

    private func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    private func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) throws {
        guard let error else { return }
        defer { idevice_error_free(error) }

        let code = error.pointee.code
        let subCode = error.pointee.sub_code
        let nativeMessage = error.pointee.message.map { String(cString: $0) } ?? "未提供詳細資料"
        let hint = diagnosticHint(for: nativeMessage)
        throw SimulationError.connectionFailed(
            "\(fallback)\n\(hint)\nidevice 錯誤 \(code)/\(subCode)：\(nativeMessage)"
        )
    }

    private func diagnosticHint(for nativeMessage: String) -> String {
        let message = nativeMessage.lowercased()
        if message.contains("pair") || message.contains("verify") || message.contains("identity") {
            return "Pairing 驗證失敗：請重新產生這部 iPhone 的 Pairing File，再匯入 GFlyer。"
        }
        if message.contains("tls") || message.contains("ssl") || message.contains("psk") {
            return "TLS 通道失敗：Pairing File 可能已失效，請重新配對後再試。"
        }
        if message.contains("rsd") || message.contains("remotexpc") || message.contains("handshake") {
            return "CoreDevice/RSD 交握失敗：請重新連接 LocalDevVPN；若仍失敗，請保留完整錯誤文字。"
        }
        if message.contains("connect")
            || message.contains("refused")
            || message.contains("unreachable")
            || message.contains("timed out")
        {
            return "TCP 連線失敗：請確認 LocalDevVPN 已連接，目標 IP 為 10.7.0.1，並關閉其他 VPN。"
        }
        return "請保留以下完整錯誤文字，以便判斷失敗階段。"
    }
}

private func developerDiskImageProgress(
    _ progress: Int,
    _ total: Int,
    _ context: UnsafeMutableRawPointer?
) {
    _ = progress
    _ = total
    _ = context
}

private struct IPv4SocketAddress {
    var value: sockaddr_in

    init?(ip: String, port: UInt16) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        let result = ip.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard result == 1 else { return nil }
        value = address
    }
}
#endif
