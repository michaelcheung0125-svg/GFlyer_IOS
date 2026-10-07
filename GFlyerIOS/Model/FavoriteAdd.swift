import Foundation

/// 地圖工具列 ☆ 的文字,三平台一字不差(GFlyer-Suite docs/features/favorite-add.md「錯誤情況與訊息」)。
/// 0.6.11 起命名對話框是自訂 sheet,和 Android 一樣顯示「名稱」標籤與等反查時的提示(規格第 5 節「iOS 0.6.11 實作重點」)。
enum FavoriteAddTexts {
    static let dialogTitle = "收藏位置"
    /// 名稱欄位上方的小字(Android 是欄位的浮動標籤)。
    static let nameLabel = "名稱"
    static let namePlaceholder = "留空就用座標當名稱"
    /// 等反查時名稱欄位下方的小字(規格 §3.3、§3.4)。結尾是一個 U+2026「…」,不是三個句點。
    static let lookingUpHint = "正在查詢地名…"
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

/// 命名 sheet 要顯示、也要收藏的座標,與名稱欄位一開始的文字。座標是按 ☆ 那一刻的收藏目標座標,
/// sheet 開著時不再跟著模擬位置變(規格待決事項 2:存下的座標等於 sheet 上顯示的座標);預填與插隊反查也看這一點所在的格子(§3.4)。
struct FavoriteNameRequest: Identifiable, Equatable {
    /// 每按一次 ☆ 一個新的 id,給 `.sheet(item:)` 分辨是哪一次打開;不算在相等裡。
    let id: UUID
    let coordinate: GeoCoordinate
    /// 這個座標所在快取格的「國家 · 城市」原文(不修剪、不截斷);快取裡沒有就是空字串。
    let suggestedName: String

    init(coordinate: GeoCoordinate, suggestedName: String, id: UUID = UUID()) {
        self.id = id
        self.coordinate = coordinate
        self.suggestedName = suggestedName
    }

    /// 只比內容:座標與預填相同就相等,不管是哪一次按 ☆。
    static func == (lhs: FavoriteNameRequest, rhs: FavoriteNameRequest) -> Bool {
        lhs.coordinate == rhs.coordinate && lhs.suggestedName == rhs.suggestedName
    }
}

/// 按地圖工具列 ☆ 時要做什麼。UI 只負責顯示。
enum FavoriteAddPrompt: Equatable {
    /// 收藏目標座標已經收藏過:不跳對話框,只顯示這則訊息。
    case alreadySaved(message: String)
    /// 跳命名 sheet。
    case askName(FavoriteNameRequest)

    /// 重複判斷用收藏目標座標(座標完全相等),不是選取點(規格待決事項 1;Android 之後也改成相同)。
    /// 預填是這一格快取裡的標籤,這裡只讀快取;快取裡沒有時,sheet 打開後才插隊反查,查到時欄位還沒鎖住才填
    /// (`FavoriteNameField`,規格 §3.4)。
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

/// 命名 sheet 的名稱欄位,照 Android `model/FavoriteAdd.kt` 的 `FavoriteNameField`(規格 §3.4)。純值型別,
/// `FavoriteNameSheetTests` 驗。
///
/// 晚到的地名只在欄位還沒鎖住時填進去。會鎖住的情況:使用者改過欄位的文字(包括打了字又全部刪光、把填好的地名刪掉),
/// 或欄位已經有過地名(打開時從快取預填,或等待中晚到的地名已經填過一次)。所以欄位最多自己變一次,
/// 快取的預填不會被換掉,使用者的修改也絕不會被蓋掉。等待結束(查不到或 10 秒逾時)之後才到的地名一律不填。
struct FavoriteNameField: Equatable {
    /// 欄位的文字。
    private(set) var text: String
    /// 鎖住之後,晚到的地名一律不填。
    private(set) var locked: Bool
    /// 等反查中:欄位下方顯示「正在查詢地名…」。只跟反查有關,使用者打字不會讓它消失。
    private(set) var isLookingUp: Bool

    /// 打開 sheet 時:快取裡有地名就預填並鎖住,沒有就空白、等反查(`suggestedName` 是空字串)。
    init(suggestedName: String) {
        text = suggestedName
        locked = !suggestedName.isEmpty
        isLookingUp = suggestedName.isEmpty
    }

    /// 使用者改了欄位的文字:換成新文字並鎖住,改成空字串也鎖住。文字沒變(只是點進欄位、移動游標)不算,
    /// 和 Compose 的 `onValueChange` 只在文字改變時呼叫相同。
    mutating func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        locked = true
    }

    /// 反查查到了:提示消失;欄位還沒鎖住就換成標籤原文(不修剪、不截斷)並鎖住。等待已經結束(查不到、逾時)就不理。
    mutating func labelArrived(_ label: String) {
        guard isLookingUp else { return }
        isLookingUp = false
        guard !locked else { return }
        text = label
        locked = true
    }

    /// 查不到(沒網路、連線逾時、非 2xx、查不到地區;這一格已被封鎖時馬上):提示消失,欄位不變,沒有任何錯誤訊息。
    mutating func lookupFailed() {
        isLookingUp = false
    }

    /// 等了 10 秒還沒有結果:提示消失,之後才到的地名也不填(標籤照樣進快取與清單)。
    mutating func timedOut() {
        isLookingUp = false
    }

    /// 把 `FavoriteNameLookup.firstOutcome` 的結果套到欄位上。
    mutating func finishLookup(_ outcome: FavoriteNameLookupOutcome) {
        switch outcome {
        case let .found(label):
            labelArrived(label)
        case .failed:
            lookupFailed()
        case .timedOut:
            timedOut()
        }
    }
}

/// 命名 sheet 等反查的結果。
enum FavoriteNameLookupOutcome: Equatable, Sendable {
    /// 查到了,是這一格的「國家 · 城市」。
    case found(String)
    /// 查不到,或這一格這次執行已被封鎖。
    case failed
    /// 10 秒內沒有結果,或等的一方已經不等了(sheet 關掉)。
    case timedOut
}

/// 命名 sheet 的 `.task` 用:同時等插隊反查與 10 秒,先到的決定結果(Android `MainViewModel.lookupRegionLabelNow`
/// 的 `withTimeoutOrNull`,規格 §3.4)。
enum FavoriteNameLookup {
    /// 最多等這麼久,從 sheet 打開時算起(Android `FavoriteAdd.NameLookupTimeoutMillis = 10_000L`)。
    static let timeoutSeconds: TimeInterval = 10

    /// 反查本身不會被取消:逾時、或 sheet 關掉(呼叫這裡的 Task 被取消)之後,請求照樣送出、標籤照樣進快取
    /// (region-labels.md §3.3),只是結果沒有人要了。
    /// - Parameters:
    ///   - seconds: 逾時的秒數。
    ///   - sleeper: 等逾時;測試換成不真的等的。被取消時要盡快回來。
    ///   - lookUp: 插隊反查,查到是標籤、查不到是 nil(`SimulationController.favoriteNameLabel(for:)`)。
    @MainActor
    static func firstOutcome(
        within seconds: TimeInterval = FavoriteNameLookup.timeoutSeconds,
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            _ = try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        },
        lookUp: @escaping @MainActor () async -> String?
    ) async -> FavoriteNameLookupOutcome {
        let (outcomes, continuation) = AsyncStream.makeStream(of: FavoriteNameLookupOutcome.self)
        // 不跟著取消:晚到的結果送進已經結束的 stream,直接丟掉
        Task { @MainActor in
            if let label = await lookUp() {
                continuation.yield(.found(label))
            } else {
                continuation.yield(.failed)
            }
        }
        let timer = Task {
            await sleeper(seconds)
            continuation.yield(.timedOut)
        }
        defer {
            timer.cancel()
            continuation.finish()
        }
        for await outcome in outcomes {
            return outcome
        }
        // 等的一方被取消(sheet 關掉):stream 結束,沒有人要看結果了
        return .timedOut
    }
}
