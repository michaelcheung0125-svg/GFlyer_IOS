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
    private var sessionIdentity: SessionIdentity?

    func testConnection(pairingFileURL: URL, pairingFileRevision: UUID, deviceIP: String) async throws {
        do {
            try await ensureSession(
                pairingFileURL: pairingFileURL,
                pairingFileRevision: pairingFileRevision,
                deviceIP: deviceIP
            )
        } catch {
            cleanup()
            throw error
        }
    }

    func setLocation(
        _ coordinate: GeoCoordinate,
        pairingFileURL: URL,
        pairingFileRevision: UUID,
        deviceIP: String
    ) async throws {
        for attempt in 0..<2 {
            do {
                try await ensureSession(
                    pairingFileURL: pairingFileURL,
                    pairingFileRevision: pairingFileRevision,
                    deviceIP: deviceIP
                )
                guard let locationSimulation else {
                    throw SimulationError.connectionFailed("定位模擬服務未建立有效連線。")
                }
                try check(
                    location_simulation_set(locationSimulation, coordinate.latitude, coordinate.longitude),
                    fallback: "無法更新模擬位置。"
                )
                return
            } catch {
                cleanup()
                guard attempt == 0, isRetryableTransportError(error) else { throw error }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    func clearLocation(
        pairingFileURL: URL,
        pairingFileRevision: UUID,
        deviceIP: String,
        tearDownSession: Bool
    ) async throws {
        for attempt in 0..<2 {
            do {
                try await ensureSession(
                    pairingFileURL: pairingFileURL,
                    pairingFileRevision: pairingFileRevision,
                    deviceIP: deviceIP
                )
                guard let locationSimulation else {
                    throw SimulationError.connectionFailed("定位模擬服務未建立有效連線。")
                }
                let error = location_simulation_clear(locationSimulation)
                try check(error, fallback: "無法清除模擬位置。")
                // 一般停止保留 session（蜂窩網路重連成本高）。完整清除才拆掉
                // session；實機觀察：即使拆掉，iOS 也不會立刻回報真實位置——
                // 定位堆疊會沿用快取的最後（模擬）定位，直到取得新的真實
                // fix（可能需要開關飛行模式或到收訊好的地方）。所以「恢復
                // 真實定位」交給上層驗證與提示，這裡不做任何保證。
                if tearDownSession { cleanup() }
                return
            } catch {
                cleanup()
                guard attempt == 0, isRetryableTransportError(error) else { throw error }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private func ensureSession(
        pairingFileURL: URL,
        pairingFileRevision: UUID,
        deviceIP: String
    ) async throws {
        let requestedIdentity = SessionIdentity(
            deviceIP: deviceIP,
            pairingFileURL: pairingFileURL.standardizedFileURL,
            pairingFileRevision: pairingFileRevision
        )
        if locationSimulation != nil, sessionIdentity == requestedIdentity { return }
        if locationSimulation != nil { cleanup() }

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
            sessionIdentity = requestedIdentity
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
        sessionIdentity = nil
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
        if message.contains("brokenpipe")
            || message.contains("broken pipe")
            || message.contains("channel closed")
            || message.contains("connection reset")
            || message.contains("not connected")
        {
            return reconnectionHint
        }
        if message.contains("connect")
            || message.contains("refused")
            || message.contains("unreachable")
            || message.contains("timed out")
        {
            return "TCP 連線失敗。\(reconnectionHint)"
        }
        return "請保留以下完整錯誤文字，以便判斷失敗階段。"
    }

    private var reconnectionHint: String {
        "通道已中斷或無法建立：使用行動網絡時，請先開啟飛行模式並重新建立通道，成功後再開回行動網絡；已連接 Wi-Fi 或個人熱點時無需開啟飛行模式，請重新連接 LocalDevVPN。同時確認 GFlyer 目標 IP 與 LocalDevVPN Device IP 相同。"
    }

    private func isRetryableTransportError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("brokenpipe")
            || message.contains("broken pipe")
            || message.contains("channel closed")
            || message.contains("connection reset")
            || message.contains("not connected")
    }
}

private struct SessionIdentity: Equatable {
    let deviceIP: String
    let pairingFileURL: URL
    let pairingFileRevision: UUID
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
