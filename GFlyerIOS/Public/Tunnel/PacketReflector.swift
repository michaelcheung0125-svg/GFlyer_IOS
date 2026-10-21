import Foundation

/// 公開版本機通道的核心（docs/APP_STORE_PLAN.md 第 12 項）：把送往目標 IP 的 IPv4 封包的來源和目的
/// 位址對調，送回 iPhone 自己。
///
/// 通道只把目標 IP 這一個位址導進來。GFlyer 連目標 IP 時，封包是「通道位址 → 目標 IP」；對調之後
/// 變成「目標 IP → 通道位址」，iPhone 就把它當成目標 IP 連進來的連線，交給自己的開發服務；
/// 開發服務的回覆同樣經過這裏對調，回到 GFlyer。封包不離開這部 iPhone。
///
/// 對調兩個位址不用重算 checksum：IPv4 標頭和 TCP、UDP 的 checksum 都是 16 bits 為單位的加總，
/// 和次序無關。這個檔案同時編進公開版的 App 和通道 extension（`GFlyerPublicTunnel`）。
struct PacketReflector: Equatable {
    /// App 經 `NETunnelProviderProtocol.providerConfiguration` 把目標 IP 交給 extension 用的鍵。
    static let targetAddressKey = "targetAddress"

    /// 目標 IP 的 4 個 bytes。
    let target: [UInt8]
    /// 通道介面自己的位址，和目標 IP 不同。
    let interfaceAddress: String

    /// `targetAddress` 不是有效的 IPv4 位址時回傳 nil。
    init?(targetAddress: String) {
        guard let target = Self.ipv4Bytes(targetAddress) else { return nil }
        self.target = target
        interfaceAddress = target == [10, 7, 0, 2] ? "10.7.0.3" : "10.7.0.2"
    }

    /// 對調後的封包；不是送往目標 IP 的 IPv4 封包回傳 nil（丟掉）。
    func reflect(_ packet: Data) -> Data? {
        var bytes = [UInt8](packet)
        guard bytes.count >= 20, bytes[0] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[0] & 0x0f) * 4
        guard headerLength >= 20, headerLength <= bytes.count,
              Array(bytes[16..<20]) == target else { return nil }
        for offset in 0..<4 {
            bytes.swapAt(12 + offset, 16 + offset)
        }
        return Data(bytes)
    }

    /// 「a.b.c.d」的 4 個 bytes。
    static func ipv4Bytes(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { part -> UInt8? in
            guard (1...3).contains(part.count), part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber) else {
                return nil
            }
            return UInt8(part)
        }
        return bytes.count == 4 ? bytes : nil
    }
}
