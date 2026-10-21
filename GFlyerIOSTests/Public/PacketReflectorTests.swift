import XCTest
@testable import GFlyerIOS

/// 本機通道對調位址的部分（`PacketReflector`）。通道 extension 本身要在實機上才跑得到。
final class PacketReflectorTests: XCTestCase {
    private let reflector = PacketReflector(targetAddress: "10.7.0.1")!

    func testSwapsSourceAndDestination() throws {
        let packet = Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1])
        let reply = try XCTUnwrap(reflector.reflect(packet))
        XCTAssertEqual(Array(reply[12..<16]), [10, 7, 0, 1])
        XCTAssertEqual(Array(reply[16..<20]), [10, 7, 0, 2])
        XCTAssertEqual(reply.count, packet.count)
        XCTAssertEqual(reply[20...], packet[20...], "TCP 的部分原封不動")
    }

    func testChecksumsStayValid() throws {
        let packet = Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1])
        XCTAssertTrue(Self.checksumsAreValid(packet), "測試用的封包本身要先對")
        let reply = try XCTUnwrap(reflector.reflect(packet))
        XCTAssertTrue(Self.checksumsAreValid(reply))
    }

    func testReflectingTwiceGivesTheOriginal() throws {
        let packet = Self.tcpPacket(from: [10, 7, 0, 1], to: [10, 7, 0, 1])
        let reply = try XCTUnwrap(reflector.reflect(packet))
        XCTAssertEqual(reflector.reflect(reply), packet)
    }

    func testKeepsHeaderOptions() throws {
        var bytes = [UInt8](Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1]))
        bytes[0] = 0x46
        bytes.insert(contentsOf: [1, 1, 1, 0], at: 20)
        let reply = try XCTUnwrap(reflector.reflect(Data(bytes)))
        XCTAssertEqual(Array(reply[12..<16]), [10, 7, 0, 1])
        XCTAssertEqual(Array(reply[20..<24]), [1, 1, 1, 0])
    }

    func testWorksOnDataSlices() throws {
        let packet = Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1])
        let padded = Data([0xff, 0xff]) + packet
        let slice = padded[2...]
        XCTAssertNotEqual(slice.startIndex, 0)
        let reply = try XCTUnwrap(reflector.reflect(slice))
        XCTAssertEqual(Array(reply[12..<16]), [10, 7, 0, 1])
    }

    func testDropsPacketsItShouldNotTouch() {
        let otherDestination = Self.tcpPacket(from: [10, 7, 0, 2], to: [8, 8, 8, 8])
        XCTAssertNil(reflector.reflect(otherDestination))

        var ipv6 = [UInt8](repeating: 0, count: 40)
        ipv6[0] = 0x60
        XCTAssertNil(reflector.reflect(Data(ipv6)))

        XCTAssertNil(reflector.reflect(Data()))
        XCTAssertNil(reflector.reflect(Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1]).prefix(19)))

        var shortHeader = [UInt8](Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1]))
        shortHeader[0] = 0x44
        XCTAssertNil(reflector.reflect(Data(shortHeader)), "標頭長度少於 20 bytes")

        var longHeader = [UInt8](Self.tcpPacket(from: [10, 7, 0, 2], to: [10, 7, 0, 1]))
        longHeader[0] = 0x4f
        XCTAssertNil(reflector.reflect(Data(longHeader)), "標頭長度比封包長")
    }

    func testTargetAddress() {
        XCTAssertEqual(PacketReflector(targetAddress: "10.7.0.1")?.target, [10, 7, 0, 1])
        XCTAssertEqual(PacketReflector(targetAddress: "10.7.0.1")?.interfaceAddress, "10.7.0.2")
        XCTAssertEqual(PacketReflector(targetAddress: "10.7.0.2")?.interfaceAddress, "10.7.0.3")
        for invalid in ["", "10.7.0", "10.7.0.1.5", "256.0.0.1", "10.7.0.-1", "10.7.0.1 ", "a.b.c.d", "10..0.1", "10.7.0.١"] {
            XCTAssertNil(PacketReflector(targetAddress: invalid), invalid)
        }
    }

    // MARK: - 測試用的封包

    /// 一個 IPv4 的 TCP SYN（20 bytes 標頭 + 20 bytes TCP），checksum 都算好。
    private static func tcpPacket(from source: [UInt8], to destination: [UInt8]) -> Data {
        var ip: [UInt8] = [0x45, 0, 0, 40, 0x12, 0x34, 0x40, 0, 64, 6, 0, 0] + source + destination
        let ipChecksum = ~onesComplementSum(ip)
        ip[10] = UInt8(ipChecksum >> 8)
        ip[11] = UInt8(ipChecksum & 0xff)
        var tcp: [UInt8] = [0xc0, 0x01, 0xc0, 0x00, 0, 0, 0, 1, 0, 0, 0, 0, 0x50, 0x02, 0xff, 0xff, 0, 0, 0, 0]
        let tcpChecksum = ~onesComplementSum(pseudoHeader(ip, length: tcp.count) + tcp)
        tcp[16] = UInt8(tcpChecksum >> 8)
        tcp[17] = UInt8(tcpChecksum & 0xff)
        return Data(ip + tcp)
    }

    private static func checksumsAreValid(_ packet: Data) -> Bool {
        let bytes = [UInt8](packet)
        let headerLength = Int(bytes[0] & 0x0f) * 4
        let header = Array(bytes[0..<headerLength])
        let tcp = Array(bytes[headerLength...])
        return onesComplementSum(header) == 0xffff
            && onesComplementSum(pseudoHeader(header, length: tcp.count) + tcp) == 0xffff
    }

    private static func pseudoHeader(_ ip: [UInt8], length: Int) -> [UInt8] {
        Array(ip[12..<20]) + [0, ip[9], UInt8(length >> 8), UInt8(length & 0xff)]
    }

    private static func onesComplementSum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index < bytes.count {
            let high = UInt32(bytes[index]) << 8
            let low = index + 1 < bytes.count ? UInt32(bytes[index + 1]) : 0
            sum += high | low
            index += 2
        }
        while sum > 0xffff {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        return UInt16(sum)
    }
}
