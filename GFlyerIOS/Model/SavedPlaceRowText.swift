import Foundation

/// 收藏位置與定位歷史清單每一列的第三行(收藏路線那一列不走這裡),和 Android `model/SavedPlaceRowText.kt`
/// 一字不差(GFlyer-Suite docs/features/region-labels.md §3.8,2026-10-08 的決定 B)。`SavedPlaceRowTextTests` 驗。
///
/// 第二行只放座標;「國家 · 城市」改接在第三行的時間後面(第三行最多折兩行,`SavedPlacesView` 的 `.lineLimit(2)`):
/// 座標一行放得完,放不下時從結尾截掉的是地區,不是座標也不是時間。
enum SavedPlaceRowText {
    /// 時間與地區之間:兩個空白 + U+00B7 + 兩個空白。和標籤內部、收藏路線列用的「 · 」(`RegionLabel.separator`)不同。
    static let separator = "  \u{00B7}  "

    /// 「收藏於 2026年9月24日 下午1:40  ·  臺灣 · 臺北市」;定位歷史的 `prefix` 是「定位於」。
    /// 還不知道地區(`regionLabel` 是 nil、空字串或只有空白,和 Kotlin 的 `isBlank()` 相同)時只有前半,連同分隔一起省略。
    static func timeLine(prefix: String, formattedTime: String, regionLabel: String?) -> String {
        let label = regionLabel.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let parts: [String?] = ["\(prefix) \(formattedTime)", label]
        return parts.compactMap { $0 }.joined(separator: separator)
    }
}
