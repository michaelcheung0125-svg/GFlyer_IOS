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

    /// 一次性的目前位置回報。
    struct CurrentLocationFix {
        let coordinate: GeoCoordinate
        /// 由軟體模擬的定位。清除模擬後若仍為 true，代表模擬位置還在生效。
        let isSimulatedBySoftware: Bool
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isBackgroundActivityActive = false

    private let manager = CLLocationManager()
    private var locationCompletion: ((Result<CurrentLocationFix, Error>) -> Void)?
    private var locationRequestStartedAt = Date.distantPast
    private var staleFallbackLocation: CLLocation?
    private var locationTimeoutTask: Task<Void, Never>?
    private var backgroundActivitySession: CLBackgroundActivitySession?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation(
        completion: @escaping (Result<CurrentLocationFix, Error>) -> Void
    ) {
        locationCompletion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginCurrentLocationRequest()
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

    private func finishLocationRequest(_ result: Result<CurrentLocationFix, Error>) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        staleFallbackLocation = nil
        let completion = locationCompletion
        locationCompletion = nil
        completion?(result)
        if isBackgroundActivityActive {
            prepareForBackgroundRouteActivity()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    /// `requestLocation()` 常常先回一筆快取的舊定位——模擬剛結束時，快取裡
    /// 正是殘留的模擬座標。改用連續更新，只接受「按下按鈕之後」產生的新定
    /// 位；逾時才退回最新的快取值。
    private func beginCurrentLocationRequest() {
        locationRequestStartedAt = Date()
        staleFallbackLocation = nil
        prepareForCurrentLocationRequest()
        manager.startUpdatingLocation()
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, locationCompletion != nil else { return }
            if let fallback = staleFallbackLocation, let fix = Self.fix(from: fallback) {
                finishLocationRequest(.success(fix))
            } else {
                finishLocationRequest(.failure(LocationError.unavailable("等不到新的定位。剛清除模擬後，iOS 可能還需要一段時間才會回報真實位置；可開關一次飛行模式、到收訊較好的位置，或稍後再試。")))
            }
        }
    }

    /// 只接受請求開始之後產生的定位（留 1 秒時鐘誤差）。
    static func isFreshFix(timestamp: Date, requestStartedAt: Date) -> Bool {
        timestamp >= requestStartedAt.addingTimeInterval(-1)
    }

    private static func fix(from location: CLLocation) -> CurrentLocationFix? {
        guard let coordinate = GeoCoordinate.validated(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else { return nil }
        return CurrentLocationFix(
            coordinate: coordinate,
            isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware ?? false
        )
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
            beginCurrentLocationRequest()
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
        if Self.isFreshFix(timestamp: location.timestamp, requestStartedAt: locationRequestStartedAt) {
            if let fix = Self.fix(from: location) {
                finishLocationRequest(.success(fix))
            }
        } else if staleFallbackLocation.map({ location.timestamp > $0.timestamp }) ?? true {
            // 舊快取先留著當逾時保底，繼續等新的
            staleFallbackLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locationCompletion != nil else { return }
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return // 暫時取不到定位，等下一筆或逾時
        }
        finishLocationRequest(.failure(LocationError.unavailable(error.localizedDescription)))
    }
}
