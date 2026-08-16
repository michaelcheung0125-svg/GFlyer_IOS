import Foundation

protocol LocationSimulationBackend: Actor {
    nonisolated var name: String { get }
    nonisolated var canControlDeviceLocation: Bool { get }

    func testConnection(pairingFileURL: URL, pairingFileRevision: UUID, deviceIP: String) async throws
    func setLocation(
        _ coordinate: GeoCoordinate,
        pairingFileURL: URL,
        pairingFileRevision: UUID,
        deviceIP: String
    ) async throws
    func clearLocation(pairingFileURL: URL, pairingFileRevision: UUID, deviceIP: String) async throws
}

actor PreviewLocationSimulationBackend: LocationSimulationBackend {
    nonisolated let name = "預覽模式"
    nonisolated let canControlDeviceLocation = false

    private var coordinate: GeoCoordinate?

    func testConnection(pairingFileURL _: URL, pairingFileRevision _: UUID, deviceIP _: String) async throws { }

    func setLocation(
        _ coordinate: GeoCoordinate,
        pairingFileURL _: URL,
        pairingFileRevision _: UUID,
        deviceIP _: String
    ) async throws {
        self.coordinate = coordinate
    }

    func clearLocation(pairingFileURL _: URL, pairingFileRevision _: UUID, deviceIP _: String) async throws {
        coordinate = nil
    }
}

enum LocationSimulationBackendFactory {
    static func makeDefault() -> any LocationSimulationBackend {
        #if GFLYER_IDEVICE
        return IdeviceLocationSimulationBackend()
        #else
        return PreviewLocationSimulationBackend()
        #endif
    }
}
