import Foundation

/// 地圖工具列 ☆ 的文字,三平台一字不差(GFlyer-Suite docs/features/favorite-add.md「錯誤情況與訊息」)。
/// 系統 alert 的文字框沒有獨立的標籤,所以 Android 的「名稱」標籤不顯示,只有提示文字(規格第 5 節)。
enum FavoriteAddTexts {
    static let dialogTitle = "收藏位置"
    static let namePlaceholder = "留空就用座標當名稱"
    static let confirmButton = "收藏"
    static let cancelButton = "取消"
    static let added = "收藏成功"
    static let alreadyExists = "此座標已經收藏過"
    /// 和 Android `ui/MainScreen.kt` 的 ☆ 相同(規格待決事項 3,0.6.9 是「收藏目前位置」)。
    static let toolbarButtonLabel = "收藏選擇位置"

    /// 名稱空白(含只有空白字元)時的名稱,例如「收藏 25.033900, 121.564500」;最長 26 個 code point,不會被截斷。
    static func defaultName(for coordinate: GeoCoordinate) -> String {
        "收藏 \(coordinate.display)"
    }
}

/// 收藏目標座標裡的「模擬位置」,對應 Android 的 `MockLocationStatus.coordinate`(規格 §3.1、§5)。
/// 只在記憶體,不存檔。
///
/// 不能直接用 `SimulationStatus`:推送失敗之後它的座標還留著,按了停止也要等 `clearLocation` 回來才重設
/// (清除失敗就一直不重設);Android 這兩種情況都已經沒有模擬位置。所以另記一份:只有推送真的成功才寫,
/// 推送失敗或按下停止(不管之後清除成功或失敗)就清掉。開始路線、開始探索不動它(Android 開始路線也不寫座標)。
struct FavoriteTargetTracker: Equatable {
    /// 最近一次成功推送的模擬位置;沒有模擬時是 nil。
    private(set) var simulated: GeoCoordinate?

    mutating func pushSucceeded(_ coordinate: GeoCoordinate) { simulated = coordinate }
    mutating func pushFailed() { simulated = nil }
    mutating func stopRequested() { simulated = nil }

    /// 收藏目標座標:模擬位置,沒有時是選取點。
    func target(selected: GeoCoordinate) -> GeoCoordinate { simulated ?? selected }
}

/// 命名對話框要顯示、也要收藏的座標,與名稱欄位一開始的文字。座標是按 ☆ 那一刻的收藏目標座標,
/// 對話框開著時不再跟著模擬位置變(規格待決事項 2:存下的座標等於對話框上顯示的座標)。
struct FavoriteNameRequest: Equatable {
    let coordinate: GeoCoordinate
    /// 這個座標所在快取格的「國家 · 城市」原文(不修剪、不截斷);快取裡沒有就是空字串。
    let suggestedName: String
}

/// 按地圖工具列 ☆ 時要做什麼。UI 只負責顯示。
enum FavoriteAddPrompt: Equatable {
    /// 收藏目標座標已經收藏過:不跳對話框,只顯示這則訊息。
    case alreadySaved(message: String)
    /// 跳命名對話框。
    case askName(FavoriteNameRequest)

    /// 重複判斷用收藏目標座標(座標完全相等),不是選取點(規格待決事項 1;Android 0.8.7 按鈕上用選取點,
    /// 記在 DRIFT D27)。預填只讀標籤快取,不送出反查:還沒收藏的位置不能送出去(規格 §3.4、
    /// region-labels.md §3.9),查到之後也不會補進已經打開的對話框。
    static func forTarget(
        _ target: GeoCoordinate,
        favorites: [SavedPlace],
        regionLabels: [String: String]
    ) -> FavoriteAddPrompt {
        if favorites.contains(where: { $0.coordinate == target }) {
            return .alreadySaved(message: FavoriteAddTexts.alreadyExists)
        }
        let suggestedName = RegionLabel.label(in: regionLabels, for: target) ?? ""
        return .askName(FavoriteNameRequest(coordinate: target, suggestedName: suggestedName))
    }
}
