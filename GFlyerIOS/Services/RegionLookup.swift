import Foundation

/// 收藏位置與收藏路線清單上的「國家 · 城市」:快取鍵、Nominatim 請求、回應 → 標籤的純函式,
/// 照 Android `RegionLookup.key` 與 `GeocoderRepository.reverseRegion`(GFlyer-Suite
/// docs/features/region-labels.md §3.2、§3.4、§3.5;對照 fixture `region/nominatim-labels.json`)。
/// ☆ 的命名 sheet 也用同一個標籤預填名稱;那一格還沒有標籤時可以插隊反查,仍守 1.1 秒的間隔
/// (`RegionLookup.lookUpUrgently`)。
enum RegionLabel {
    /// 國家與城市之間、以及收藏路線列接標籤用的分隔:U+0020 U+00B7 U+0020。
    static let separator = " · "
    /// 城市依序取第一個不是空白的欄位。其他欄位一律不看,包括日本、中國、荷蘭的省級常用的 `province`。
    static let cityFields = ["city", "town", "municipality", "village", "county", "state_district", "state"]
    /// Android 是連線 8 秒、讀取 8 秒;`URLRequest` 只有一個閒置逾時,兩段都受它限制。
    static let timeoutSeconds: TimeInterval = 8

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

    /// `GFlyer/<版本> (iOS)`,和 `AppUpdateChecker` 相同。Nominatim 的規範要求能辨識 App,
    /// 不能用 URLSession 預設的 User-Agent。
    static func userAgent(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "GFlyer/\(version) (iOS)"
    }

    /// `GET https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=zh-TW&lat=…&lon=…`。
    /// 送的是收藏的原始座標(不是快取格的中心),`String(Double)` 是最短可還原的寫法;
    /// `zoom=10` 是城市層級,語言固定 zh-TW、不跟系統語言。
    static func request(for coordinate: GeoCoordinate, userAgent: String) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "nominatim.openstreetmap.org"
        components.path = "/reverse"
        components.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "zoom", value: "10"),
            URLQueryItem(name: "accept-language", value: "zh-TW"),
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// 整個 HTTP 回應 → 標籤(§3.5 第 1–3 步);nil 代表這次查詢失敗。`status` 是 nil 代表連線本身失敗。
    /// 狀態碼不在 200–299 就不讀 body;body 必須是 JSON 物件,`address` 也必須是物件 ——
    /// 查不到的地方(例如海上)Nominatim 回 `200 {"error":"Unable to geocode"}`,落在這一條。
    static func label(status: Int?, body: Data?) -> String? {
        guard let status, (200...299).contains(status), let body,
              let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let address = root["address"] as? [String: Any] else { return nil }
        return label(address: address)
    }

    /// `address` → 「國家 · 城市」(§3.5 第 4–8 步);兩者都沒有是 nil。
    /// 只認字串值:數字、布林、JSON null 都當作沒有(Android 裝置上的 org.json 會把 null 變成 "null",
    /// 規格說不要模仿)。取到的值原樣使用:不修剪、不截斷、不處理「達卡;达卡」這種分號並列寫法。
    static func label(address: [String: Any]) -> String? {
        let country = nonBlank(address["country"])
        let city = cityFields.compactMap { nonBlank(address[$0]) }.first
        // 城市和國家逐字相同(例如新加坡)就丟掉城市,而且不再往下一個欄位找
        let keptCity = city == country ? nil : city
        let parts = [country, keptCity].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    /// 空字串或只有空白字元(含全形空白、不換行空白、tab、換行)算沒有,和 Kotlin 的 `isBlank()` 相同。
    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// 一次反查的 HTTP 結果。
struct RegionLookupResponse: Equatable, Sendable {
    let statusCode: Int
    let body: Data
}

/// 送出反查請求。回傳 nil 代表連線本身失敗(沒網路、逾時、憑證錯誤……)。測試換成假的,不連網。
protocol RegionLookupTransport: Sendable {
    func response(for request: URLRequest) async -> RegionLookupResponse?
}

/// 兩次請求之間的等待。測試換成只記錄、不真的等的假時鐘。
protocol RegionLookupClock: Sendable {
    func sleep(seconds: TimeInterval) async
}

struct URLSessionRegionLookupTransport: RegionLookupTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func response(for request: URLRequest) async -> RegionLookupResponse? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            return RegionLookupResponse(statusCode: http.statusCode, body: data)
        } catch {
            return nil
        }
    }
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
/// - Nominatim 的規範是每秒最多一次請求:同一時間只有一個請求,由單一工作依佇列順序處理;每次真的送出請求之後
///   (成功或失敗)等 1.1 秒才處理下一筆。已經有快取而跳過的不等,第一筆也不等。
/// - 一般請求(收藏清單)排在隊尾。已經有快取、已經在佇列裡或正在查、這次執行被封鎖的快取鍵一律跳過,
///   所以同一格只送一個座標,呼叫端很頻繁地送同一份清單也不會多送請求。
/// - ☆ 的命名 sheet 可以插隊(`lookUpUrgently`,2026-10-08 起):排到最前面(最新的優先),仍守 1.1 秒的間隔,
///   正在進行的請求不會被中斷;同一格在佇列裡最多一筆(一般 + 緊急合計)。
/// - 一般請求查失敗就封鎖那一格到下次啟動(新的 `SimulationController`):不重試、不寫進快取,使用者也看不到任何訊息。
///   緊急請求查失敗不封鎖:之後一次一般請求、或再按 ☆ 還能再排;一樣不會自己重試。
/// - 查到的結果存在自己的 `UserDefaults` 鍵,不過期,不隨刪除收藏、清除歷史、還原備份而清掉,也不在備份裡。
@MainActor
final class RegionLookup {
    /// 值是 JSON 編碼的 `[快取鍵: 標籤]`。和 `LocalDataSnapshot` 分開:標籤是可以重算的衍生資料,
    /// 放在獨立的鍵裡,收藏的資料格式與備份都不用動,舊版也只是不認得這個鍵。
    static let storageKey = "gflyer.region-labels.v1"
    /// 上一個請求結束到下一個請求開始至少隔這麼久。
    static let requestIntervalSeconds: TimeInterval = 1.1

    /// 已知的「快取鍵 → 國家 · 城市」,鍵用 `RegionLabel.key(for:)` 算。
    private(set) var labels: [String: String]
    /// 每查到一筆就用新的 `labels` 呼叫一次;`SimulationController` 用它更新畫面。
    var onLabelsChange: (([String: String]) -> Void)?

    private let defaults: UserDefaults
    private let transport: any RegionLookupTransport
    private let clock: any RegionLookupClock
    private let userAgent: String
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
        transport: any RegionLookupTransport = URLSessionRegionLookupTransport(),
        clock: any RegionLookupClock = TaskSleepRegionLookupClock(),
        userAgent: String = RegionLabel.userAgent()
    ) {
        self.defaults = defaults
        self.transport = transport
        self.clock = clock
        self.userAgent = userAgent
        labels = Self.loadCache(from: defaults)
    }

    /// 一般請求:這些座標的地區還沒查過就依序排進隊尾;已知的、排過隊的(在佇列裡或正在查)、這次被封鎖的都跳過。
    func request(_ coordinates: [GeoCoordinate]) {
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
    func lookUpUrgently(_ coordinate: GeoCoordinate) async -> String? {
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
            guard let request = RegionLabel.request(for: coordinate, userAgent: userAgent) else {
                finish(key, label: nil)
                continue
            }
            let response = await transport.response(for: request)
            let label = RegionLabel.label(status: response?.statusCode, body: response?.body)
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
