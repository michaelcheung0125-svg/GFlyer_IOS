import Foundation

#if GFLYER_IDEVICE
import idevice

/// 用上游 idevice `ffi/src/pairing_host.rs` 的三個函式當配對主機（docs/APP_STORE_PLAN.md 第 3、4 項）。
/// 每個實例是一個新的主機身分；配對成功之後，裝置記住的就是這個身分，配對檔裏也是它。
final class IdevicePairingHostEngine: PairingHostEngine {
    /// 「設定」的配對清單上顯示的名稱。
    static let hostName = "GFlyer"

    let serviceName: String
    let txtRecord: [String: String]
    private let handle: OpaquePointer

    init(name: String = IdevicePairingHostEngine.hostName) throws {
        var handle: OpaquePointer?
        var serviceID: UnsafeMutablePointer<CChar>?
        var txtData: UnsafeMutablePointer<UInt8>?
        var txtLength: UInt = 0
        // model 傳 NULL 用上游的預設值；最後一個參數是主機自己的 altIRK，
        // 只有配對之後要再廣播同一個主機時才需要，GFlyer 配對完就不再廣播。
        // init 還沒初始化完所有屬性，用型別名稱而不是 Self 呼叫。
        try IdevicePairingHostEngine.check(
            pairable_host_prepare(name, nil, false, &handle, &serviceID, &txtData, &txtLength, nil),
            fallback: "無法準備配對。"
        )
        defer {
            idevice_string_free(serviceID)
            idevice_data_free(txtData, txtLength)
        }
        guard let handle else {
            throw PairingHostError.idevice("無法準備配對：idevice 沒有傳回主機身分。")
        }
        do {
            guard let serviceID, let txtData else {
                throw PairingHostError.idevice("無法準備配對：idevice 沒有傳回 Bonjour 資料。")
            }
            let txt = Data(bytes: txtData, count: Int(txtLength))
            txtRecord = try PairingHostTXTRecord.dictionary(fromPropertyList: txt)
            serviceName = String(cString: serviceID)
        } catch {
            pairable_host_free(handle)
            throw error
        }
        self.handle = handle
    }

    deinit {
        pairable_host_free(handle)
    }

    func pair(overConnection socket: Int32, onPIN: @escaping (String) -> Void) throws -> PairingHostResult {
        let relay = Unmanaged.passRetained(PINRelay(onPIN)).toOpaque()
        defer { Unmanaged<PINRelay>.fromOpaque(relay).release() }

        var pairingFile: OpaquePointer?
        // 會一直擋住，直到配對成功、失敗，或 PairingHostSession.cancel() 對這個 socket 呼叫 shutdown。
        let error = pairable_host_accept_fd(
            handle,
            socket,
            { pin, context in
                guard let pin, let context else { return }
                Unmanaged<PINRelay>.fromOpaque(context).takeUnretainedValue().onPIN(String(cString: pin))
            },
            relay,
            nil,
            &pairingFile
        )
        defer {
            if let pairingFile { rp_pairing_file_free(pairingFile) }
        }
        try Self.check(error, fallback: "配對沒有成功。")
        guard let pairingFile else {
            throw PairingHostError.idevice("配對沒有成功：idevice 沒有傳回配對檔。")
        }

        var bytes: UnsafeMutablePointer<UInt8>?
        var length: UInt = 0
        try Self.check(rp_pairing_file_to_bytes(pairingFile, &bytes, &length), fallback: "無法讀出配對檔。")
        defer { idevice_data_free(bytes, length) }
        guard let bytes else {
            throw PairingHostError.idevice("無法讀出配對檔：idevice 沒有傳回內容。")
        }
        return PairingHostResult(pairingFile: Data(bytes: bytes, count: Int(length)))
    }

    private static func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) throws {
        guard let error else { return }
        defer { idevice_error_free(error) }
        let nativeMessage = error.pointee.message.map { String(cString: $0) } ?? "未提供詳細資料"
        let hint = nativeMessage.lowercased().contains("srp") ? "\n可能是 PIN 打錯了。" : ""
        throw PairingHostError.idevice(
            "\(fallback)\(hint)\nidevice 錯誤 \(error.pointee.code)/\(error.pointee.sub_code)：\(nativeMessage)"
        )
    }
}

/// 把 Swift closure 交給 C callback 的 context 指標。
private final class PINRelay {
    let onPIN: (String) -> Void

    init(_ onPIN: @escaping (String) -> Void) {
        self.onPIN = onPIN
    }
}
#endif
