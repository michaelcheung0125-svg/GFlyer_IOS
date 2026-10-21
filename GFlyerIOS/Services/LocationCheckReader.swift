import Combine
import CoreLocation
import UIKit

/// 定位檢查頁讀位置用（GFlyer-Suite `docs/features/location-check.md` 3.2）：頁面開著、App 在前景時
/// `start`，離開或到背景時 `stop`；位置不儲存、不傳送。
///
/// 用自己的 `CLLocationManager`，不和 `DeviceLocationService` 共用：那一個在單次定位完成時會停止更新，
/// 背景路線也會改它的精度設定。
@MainActor
final class LocationCheckReader: NSObject, ObservableObject {
    /// iOS 最近交給 App 的一個位置，連同頁面要顯示的精度和時間。
    struct Fix: Equatable {
        let received: ReceivedLocation
        /// iOS 沒有給精度（`horizontalAccuracy` 是負的）時是 nil。
        let accuracyMetres: Double?
        let timestamp: Date
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var fix: Fix?
    /// iOS 報告讀不到位置（不是暫時的 `locationUnknown`，也不是沒有權限）；之後收到位置就變回 false。
    @Published private(set) var updatesFailed = false

    private let manager = CLLocationManager()
    private var isReading = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var hasPermission: Bool { Self.isAuthorized(authorizationStatus) }

    func start() {
        isReading = true
        if hasPermission { manager.startUpdatingLocation() }
    }

    func stop() {
        isReading = false
        manager.stopUpdatingLocation()
    }

    /// 「允許定位權限」：還沒問過就跳系統的詢問；拒絕過或受限制就開 iOS 設定裏 GFlyer 的那一頁。
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// iOS 整部手機關了定位服務時也回報 `denied`。
    nonisolated static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// 沒有 `sourceInformation` 算真實位置，和「完整清除」的驗證、「目前位置」按鈕相同。
    nonisolated static func fix(from location: CLLocation) -> Fix? {
        guard let coordinate = GeoCoordinate.validated(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else { return nil }
        return Fix(
            received: ReceivedLocation(
                coordinate: coordinate,
                isSimulated: location.sourceInformation?.isSimulatedBySoftware ?? false
            ),
            accuracyMetres: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            timestamp: location.timestamp
        )
    }
}

// 回呼落在建立 manager 的主執行緒上；和 `DeviceLocationService` 一樣標 nonisolated，
// 用 `MainActor.assumeIsolated` 同步地存取狀態。
extension LocationCheckReader: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationStatus = manager.authorizationStatus
            // 使用者剛在詢問裏允許，或從 iOS 設定改了回來
            if isReading, hasPermission { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last, let fix = Self.fix(from: location) else { return }
            self.fix = fix
            updatesFailed = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            // 暫時取不到定位是等下一筆；沒有權限由 `needsPermission` 處理
            if let clError = error as? CLError, clError.code == .locationUnknown || clError.code == .denied { return }
            updatesFailed = true
        }
    }
}
