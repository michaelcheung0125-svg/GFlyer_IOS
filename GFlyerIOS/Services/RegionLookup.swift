import Foundation

/// 收藏位置與收藏路線清單上的「國家 · 城市」:快取鍵和組標籤共用的規則,照 Android `RegionLookup.key`
/// (GFlyer-Suite docs/features/region-labels.md §3.2、§3.5)。反查送去哪個服務由版本決定
/// (`Edition.makeRegionLabelSource()`):親友版是 Nominatim(`Family/Services/NominatimRegionLabels.swift`),
/// 公開版是 Apple 的地點服務(`Public/Services/AppleGeocoderRegionLabels.swift`,§3.5a,DRIFT D33)。
/// ☆ 的命名 sheet 也用同一個標籤預填名稱;那一格還沒有標籤時可以插隊反查,仍守 1.1 秒的間隔
/// (`RegionLookup.lookUpUrgently`)。
enum RegionLabel {
    /// 國家與城市之間、以及收藏路線列接標籤用的分隔:U+0020 U+00B7 U+0020。
    static let separator = " · "

    /// 緯度、經度各四捨五入到小數 2 位(南北約 1.1 公里一格),同一格的收藏共用一個標籤。
    /// 不帶 locale 的 `String(format:)` 小數點固定是「.」;-0.001 是「-0.00」,和「0.00」是不同的鍵,
    /// 和 Android 相同。剛好落在 5 的值兩個平台捨入方向可能不同,鍵只在同一台裝置上用,不處理。
    static func key(for coordinate: GeoCoordinate) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    /// 清單顯示用:還沒查到或查不到就是 nil,畫面上連同分隔一起省略。
    static func label(in labels: [String: String], for coordinate: GeoCoordinate) -> String? {
        labels[key(for: coordinate)]
    }

    /// 依「國家、城市」的順序接起來;兩者都沒有是 nil。城市和國家逐字相同(例如新加坡)就丟掉城市,
    /// 呼叫端也不再往下一個欄位找(§3.5 第 6–7 步、§3.5a 第 3–4 步)。取到的值原樣使用,不修剪、不截斷。
    static func join(country: String?, city: String?) -> String? {
        let keptCity = city == country ? nil : city
        let parts = [country, keptCity].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    /// 空字串或只有空白字元(含全形空白、不換行空白、tab、換行)算沒有,和 Kotlin 的 `isBlank()` 相同。
    static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// 反查一個座標所在的「國家 · 城市」。查不到、沒網路、服務出錯都回 nil,使用者看不到任何錯誤(§3.6)。
/// 每個版本一個(`Edition.makeRegionLabelSource()`);測試換成假的,不連網。
protocol RegionLabelSource: Sendable {
    func label(for coordinate: GeoCoordinate) async -> String?
}

/// 兩次請求之間的等待。測試換成只記錄、不真的等的假時鐘。
protocol RegionLookupClock: Sendable {
    func sleep(seconds: TimeInterval) async
}

struct TaskSleepRegionLookupClock: RegionLookupClock {
    func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// 收藏位置與收藏路線第一點的「國家 · 城市」反查佇列與本機快取,照 Android `data/RegionLookup.kt` 與
/// `data/RegionLookupQueue.kt`(GFlyer-Suite docs/features/region-labels.md §3.1、§3.3、§3.6、§3.7)。
/// 由 `SimulationController` 持有。
///
/// - Nominatim 的規範是每秒最多一次請求,公開版用的 Apple 地點服務也有頻率限制,兩個版本照同一個節奏:
///   同一時間只有一個請求,由單一工作依佇列順序處理;每次真的送出請求之後(成功或失敗)等 1.1 秒才處理下一筆。
///   已經有快取而跳過的不等,第一筆也不等。
/// - 一般請求(收藏清單)排在隊尾。已經有快取、已經在佇列裡或正在查、這次執行被封鎖的快取鍵一律跳過,
///   所以同一格只送一個座標,呼叫端很頻繁地送同一份清單也不會多送請求。
/// - ☆ 的命名 sheet 可以插隊(`lookUpUrgently`,2026-10-08 起):排到最前面(最新的優先),仍守 1.1 秒的間隔,
///   正在進行的請求不會被中斷;同一格在佇列裡最多一筆(一般 + 緊急合計)。
/// - 一般請求查失敗就封鎖那一格到下次啟動(新的 `SimulationController`):不重試、不寫進快取,使用者也看不到任何訊息。
///   緊急請求查失敗不封鎖:之後一次一般請求、或再按 ☆ 還能再排;一樣不會自己重試。
/// - 查到的結果存在自己的 `UserDefaults` 鍵,不過期,不隨刪除收藏、清除歷史、還原備份而清掉,也不在備份裡。
/// - 要先取得同意的版本(公開版,region-labels.md 3.10)在使用者按「允許」之前不送出任何反查。答案也存在
///   自己的 `UserDefaults` 鍵,只對這部手機有效,不在備份裡;甚麼時候問由 `SimulationController` 決定。
@MainActor
final class RegionLookup {
    /// 值是 JSON 編碼的 `[快取鍵: 標籤]`。和 `LocalDataSnapshot` 分開:標籤是可以重算的衍生資料,
    /// 放在獨立的鍵裡,收藏的資料格式與備份都不用動,舊版也只是不認得這個鍵。
    static let storageKey = "gflyer.region-labels.v1"
    /// 同意的答案(`RegionLookupConsent` 的 raw value);沒有存過是還沒問。
    static let consentStorageKey = "gflyer.region-lookup-consent.v1"
    /// 上一個請求結束到下一個請求開始至少隔這麼久。
    static let requestIntervalSeconds: TimeInterval = 1.1

    /// 已知的「快取鍵 → 國家 · 城市」,鍵用 `RegionLabel.key(for:)` 算。
    private(set) var labels: [String: String]
    /// 每查到一筆就用新的 `labels` 呼叫一次;`SimulationController` 用它更新畫面。
    var onLabelsChange: (([String: String]) -> Void)?
    /// 自動反查要先取得同意(公開版)。不用問的版本(親友版)一律當成允許。
    let asksFirst: Bool
    /// 使用者對「顯示收藏的國家與城市？」的答案。
    private(set) var consent: RegionLookupConsent

    private let defaults: UserDefaults
    private let source: any RegionLabelSource
    private let clock: any RegionLookupClock
    /// 排隊中、還沒處理的座標,依送出的順序;同一個快取鍵最多一筆。只在記憶體裡:App 結束時還沒查的,
    /// 下次啟動會因為沒有快取再排進來。
    private var pending: [GeoCoordinate] = []
    /// 這次執行排過隊的鍵(在 `pending` 裡、正在查,或已經處理完)。處理完的鍵不是進了快取就是進了 `failed`,
    /// 效果相同,所以一般不移除(和 Android 一樣)。唯一的例外:`urgent` 裡的鍵查失敗時從這裡移除、不進 `failed`,
    /// 之後一次一般請求還能再排(region-labels.md §3.3、§3.6)。
    private var queued: Set<String> = []
    /// 這次執行被封鎖的鍵:一般請求查失敗過,一般與緊急請求都不再送。
    private var failed: Set<String> = []
    /// 最近一次由緊急請求排進佇列、或搬到最前面的鍵(Android `RegionLookupQueue.urgent`)。查失敗時不封鎖;
    /// 查到、或處理前已經有快取時移除。緊急請求等的是正在查的一般請求時不加進來,那一筆失敗照一般規則封鎖。
    private var urgent: Set<String> = []
    /// 等某一格結果的緊急請求(☆ 的命名 sheet)。那一格處理完(查到、失敗、處理前已有快取)就全部交出結果並移除。
    /// 等待的一方不等了(sheet 關掉、逾時)也不移除:結果照樣交給它,請求也照樣送出。
    private var waiters: [String: [CheckedContinuation<String?, Never>]] = [:]
    private var worker: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        source: any RegionLabelSource = Edition.makeRegionLabelSource(),
        clock: any RegionLookupClock = TaskSleepRegionLookupClock(),
        asksFirst: Bool = Edition.regionLookupConsentService != nil
    ) {
        self.defaults = defaults
        self.source = source
        self.clock = clock
        self.asksFirst = asksFirst
        labels = Self.loadCache(from: defaults)
        consent = defaults.string(forKey: Self.consentStorageKey).flatMap(RegionLookupConsent.init(rawValue:)) ?? .unasked
    }

    /// 可以送出反查、顯示標籤、按 ☆ 時預填地名。
    var lookupsAllowed: Bool {
        RegionLookupConsentRules.lookupsAllowed(asksFirst: asksFirst, consent: consent)
    }

    /// 記下使用者的答案。收回同意時,還在排隊、沒送出的一併拿掉(`clearPending()`)。
    func setConsent(_ consent: RegionLookupConsent) {
        self.consent = consent
        defaults.set(consent.rawValue, forKey: Self.consentStorageKey)
        if !lookupsAllowed { clearPending() }
    }

    /// 一般請求:這些座標的地區還沒查過就依序排進隊尾;已知的、排過隊的(在佇列裡或正在查)、這次被封鎖的都跳過。
    /// 還沒取得同意時不排。
    func request(_ coordinates: [GeoCoordinate]) {
        guard lookupsAllowed else { return }
        for coordinate in coordinates {
            let key = RegionLabel.key(for: coordinate)
            guard labels[key] == nil, !queued.contains(key), !failed.contains(key) else { continue }
            queued.insert(key)
            pending.append(coordinate)
        }
        startWorkerIfNeeded()
    }

    /// 緊急請求(☆ 的命名 sheet;region-labels.md §3.3、favorite-add.md §3.4):這一格還沒有標籤就插到佇列最前面,
    /// 等到結果為止。查到是標籤;查不到、或這一格這次執行已被封鎖是 nil。送的是 `coordinate` 原值,不是格子中心。
    ///
    /// - 已有快取:直接回傳標籤,不送。被封鎖:馬上回 nil,不送。
    /// - 還在佇列裡沒送出:從原位置移出,換成 `coordinate` 插到最前面;佇列裡仍只有一筆。
    /// - 正在查:不再排,等那一筆的結果(那一筆仍算原本的請求:一般請求失敗照樣封鎖)。
    /// - 其他:記進排過隊,插到最前面(也排在先前還沒送出的緊急請求前面)。
    ///
    /// 間隔不變,由同一個工作照 1.1 秒處理;佇列閒著而且間隔已經過了就馬上送。等待的一方被取消(sheet 關掉、逾時)
    /// 不撤回請求:照樣送出、照樣寫進快取,結果也照樣交回來。10 秒的上限由呼叫端自己算。
    /// 還沒取得同意時不排,馬上回 nil。
    func lookUpUrgently(_ coordinate: GeoCoordinate) async -> String? {
        guard lookupsAllowed else { return nil }
        let key = RegionLabel.key(for: coordinate)
        // 檢查狀態、排隊與掛上等待者都在 continuation 的本體裡:本體同步執行,中間沒有 `await`,
        // `finish` 不會插在中間記下結果、讓這個等待者拿不到(Android 用同一把鎖做到)
        return await withCheckedContinuation { continuation in
            guard enqueueUrgently(coordinate, key: key) else {
                // 已有快取或被封鎖:不排、不等
                continuation.resume(returning: labels[key])
                return
            }
            waiters[key, default: []].append(continuation)
            startWorkerIfNeeded()
        }
    }

    /// 收回同意時(Android `RegionLookupQueue.clearPending`,region-labels.md 3.10):還在排隊、沒送出的一併拿掉,
    /// 等它們的 ☆ 拿到 nil;這些鍵不算排過隊,之後再允許時可以重新排,這次已失敗的照舊封鎖。
    /// 正在查的那一筆已經送出,不撤回;查到的照樣進快取(沒有同意時清單不顯示,見 `SimulationController`)。
    func clearPending() {
        let keys = pending.map { RegionLabel.key(for: $0) }
        pending.removeAll()
        for key in keys {
            queued.remove(key)
            urgent.remove(key)
            for waiter in waiters.removeValue(forKey: key) ?? [] {
                waiter.resume(returning: nil)
            }
        }
    }

    /// 排隊中、還沒送出的座標,依送出的順序。給測試看佇列,App 不用。
    var pendingCoordinates: [GeoCoordinate] { pending }

    /// 有幾個緊急請求在等這一格的結果。給測試用,App 不用。
    func waiterCount(for coordinate: GeoCoordinate) -> Int {
        waiters[RegionLabel.key(for: coordinate)]?.count ?? 0
    }

    /// 等佇列處理完。App 不需要等,給測試用。
    func waitUntilIdle() async {
        if let worker { await worker.value }
    }

    /// 照 Android `RegionLookupQueue.enqueueUrgent` 排進佇列。回傳之後會不會有這一格的結果:
    /// 已有快取或被封鎖是 false(不排),其他(排進去、搬到最前面、正在查)是 true。
    private func enqueueUrgently(_ coordinate: GeoCoordinate, key: String) -> Bool {
        guard labels[key] == nil, !failed.contains(key) else { return false }
        if let index = pending.firstIndex(where: { RegionLabel.key(for: $0) == key }) {
            // 同一格換成這次的座標(使用者要收藏的那一點),搬到最前面
            pending.remove(at: index)
            pending.insert(coordinate, at: 0)
            urgent.insert(key)
        } else if !queued.contains(key) {
            queued.insert(key)
            pending.insert(coordinate, at: 0)
            urgent.insert(key)
        }
        // 其他:排過隊、不在佇列裡、沒有快取也沒被封鎖,就是正在查;不再排,等那一筆的結果
        return true
    }

    /// 佇列閒著就開始處理。上一個工作結束時最後一次等待已經等完,所以新的工作馬上送出也不會太早。
    private func startWorkerIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await drain()
        }
    }

    /// 單一工作依序處理佇列。整段在主執行緒上,只有等網路與等間隔時讓出,所以途中加進來的一般請求接在後面、
    /// 緊急請求插在最前面;佇列清空時的最後一次等待也已經等完,之後再開始的工作不會太早送出。
    private func drain() async {
        while !pending.isEmpty {
            let coordinate = pending.removeFirst()
            let key = RegionLabel.key(for: coordinate)
            if let known = labels[key] {
                // 處理前已經有快取:不送、不等,但等這一格的一樣要拿到標籤
                finish(key, label: known)
                continue
            }
            let label = await source.label(for: coordinate)
            if let label {
                // 先寫好快取再交出結果:等待者醒來時,清單與下次預填都已經看得到這個標籤
                labels[key] = label
                persist()
                onLabelsChange?(labels)
            }
            finish(key, label: label)
            await clock.sleep(seconds: Self.requestIntervalSeconds)
        }
        worker = nil
    }

    /// 記下這一格的結果並交給它所有的等待者(Android `RegionLookup.finish` 與 `RegionLookupQueue.markDone` /
    /// `markFailed`)。記結果與取走等待者在同一段沒有 `await` 的程式裡:`lookUpUrgently` 要嘛在這之前掛上
    /// (拿到這一次的結果),要嘛在之後才來(看得到快取、封鎖,或照規則重新排隊)。
    private func finish(_ key: String, label: String?) {
        if label != nil {
            urgent.remove(key)
        } else if urgent.remove(key) != nil {
            // 緊急請求查失敗不封鎖:放掉這一格,之後一次一般請求或再按 ☆ 還能再排
            queued.remove(key)
        } else {
            failed.insert(key)
        }
        let resumed = waiters.removeValue(forKey: key) ?? []
        for waiter in resumed {
            waiter.resume(returning: label)
        }
    }

    /// 每查到一筆就立刻寫回。
    private func persist() {
        guard let data = try? JSONEncoder().encode(labels) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// 沒有存過、不是 Data 或解不開都當作沒有快取,不影響其他資料。
    private static func loadCache(from defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: storageKey),
              let cache = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return cache
    }
}
