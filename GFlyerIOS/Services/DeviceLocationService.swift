import Combine
import CoreLocation
import Foundation

@MainActor
final class DeviceLocationService: NSObject, ObservableObject {
    enum LocationError: LocalizedError {
        case permissionDenied
        case permissionRestricted
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "定位權限已關閉。請到 iPhone 設定 > 私隱與保安 > 定位服務 > GFlyer，選擇「使用 App 期間」。"
            case .permissionRestricted:
                return "這部 iPhone 限制了定位服務，GFlyer 無法取得目前位置或維持背景路線。"
            case let .unavailable(message):
                return "無法取得目前位置：\(message)"
            }
        }
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isBackgroundActivityActive = false

    private let manager = CLLocationManager()
    private var locationCompletion: ((Result<GeoCoordinate, Error>) -> Void)?
    private var backgroundActivitySession: CLBackgroundActivitySession?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation(
        completion: @escaping (Result<GeoCoordinate, Error>) -> Void
    ) {
        locationCompletion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            prepareForCurrentLocationRequest()
            manager.requestLocation()
        case .denied:
            finishLocationRequest(.failure(LocationError.permissionDenied))
        case .restricted:
            finishLocationRequest(.failure(LocationError.permissionRestricted))
        @unknown default:
            finishLocationRequest(.failure(LocationError.unavailable("未知的定位權限狀態")))
        }
    }

    func startBackgroundRouteActivity() -> Bool {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return false
        case .denied, .restricted:
            return false
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isBackgroundActivityActive else { return true }
            prepareForBackgroundRouteActivity()
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            backgroundActivitySession = CLBackgroundActivitySession()
            manager.startUpdatingLocation()
            isBackgroundActivityActive = true
            return true
        @unknown default:
            return false
        }
    }

    func stopBackgroundRouteActivity() {
        guard isBackgroundActivityActive else { return }
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        isBackgroundActivityActive = false
    }

    var backgroundPermissionMessage: String {
        switch manager.authorizationStatus {
        case .notDetermined:
            return "背景路線需要定位權限。請在系統提示選擇「允許使用 App 期間」，然後再按開始。"
        case .denied:
            return LocationError.permissionDenied.localizedDescription
        case .restricted:
            return LocationError.permissionRestricted.localizedDescription
        case .authorizedAlways, .authorizedWhenInUse:
            return "背景路線定位服務尚未啟動。"
        @unknown default:
            return "無法確認背景路線所需的定位權限。"
        }
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .notDetermined: return "尚未要求"
        case .restricted: return "受系統限制"
        case .denied: return "已拒絕"
        case .authorizedAlways: return "永遠允許"
        case .authorizedWhenInUse: return "使用期間允許"
        @unknown default: return "未知"
        }
    }

    private func finishLocationRequest(_ result: Result<GeoCoordinate, Error>) {
        let completion = locationCompletion
        locationCompletion = nil
        completion?(result)
        if isBackgroundActivityActive {
            prepareForBackgroundRouteActivity()
        }
    }

    private func prepareForCurrentLocationRequest() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
    }

    private func prepareForBackgroundRouteActivity() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 10
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }
}

extension DeviceLocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isBackgroundActivityActive,
           manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        {
            stopBackgroundRouteActivity()
        }
        guard locationCompletion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            prepareForCurrentLocationRequest()
            manager.requestLocation()
        case .denied:
            finishLocationRequest(.failure(LocationError.permissionDenied))
        case .restricted:
            finishLocationRequest(.failure(LocationError.permissionRestricted))
        case .notDetermined:
            break
        @unknown default:
            finishLocationRequest(.failure(LocationError.unavailable("未知的定位權限狀態")))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationCompletion != nil, let location = locations.last else { return }
        finishLocationRequest(.success(GeoCoordinate(location.coordinate)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locationCompletion != nil else { return }
        finishLocationRequest(.failure(LocationError.unavailable(error.localizedDescription)))
    }
}
