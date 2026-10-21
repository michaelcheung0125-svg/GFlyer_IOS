import CoreLocation

/// 公開版的「國家 · 城市」反查:用 Apple 的地點服務(`CLGeocoder`),不連 Nominatim
/// (GFlyer-Suite docs/features/region-labels.md 3.5a,DRIFT D33;docs/APP_STORE_PLAN.md 第 17 項)。
/// 公開的 Nominatim 只准全部用戶合計每秒一次,上了 App Store 一定超過;Apple 的服務不用金鑰、不用後端。
/// 照 Android 公開版的 `AndroidGeocoderPlaceLookup.reverseRegion`:語言固定繁體中文(台灣),不跟系統語言;
/// 查不到、沒網路、被限流都當成失敗(§3.6)。佇列、1.1 秒的間隔和快取照舊由 `RegionLookup` 處理。
struct AppleGeocoderRegionLabelSource: RegionLabelSource {
    /// Android 是 `Locale.TAIWAN`,和 Nominatim 的 `accept-language=zh-TW` 一樣。
    static let locale = Locale(identifier: "zh_TW")

    func label(for coordinate: GeoCoordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // 每次一個新的 CLGeocoder:同一個 CLGeocoder 同時只能查一個,佇列本來也只有一個請求在進行
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Self.locale).first
        else { return nil }
        return RegionLabel.label(
            country: placemark.country,
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea
        )
    }
}

extension RegionLabel {
    /// 系統地點服務的地址 → 「國家 · 城市」(§3.5a;fixture `region/platform-geocoder-labels.json`,
    /// Android 公開版 `PlatformGeocoderText.regionLabel`)。`CLPlacemark` 的 `country`、`locality`、
    /// `subAdministrativeArea`、`administrativeArea` 對應 Android 的 `countryName`、`locality`、`subAdminArea`、`adminArea`。
    /// 城市依序取 `locality`、`subAdministrativeArea`、`administrativeArea` 裏第一個不是空白的;其他欄位不看。
    static func label(
        country: String?,
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?
    ) -> String? {
        let city = [locality, subAdministrativeArea, administrativeArea].lazy.compactMap { nonBlank($0) }.first
        return join(country: nonBlank(country), city: city)
    }
}
