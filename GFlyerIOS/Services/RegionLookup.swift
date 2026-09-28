import Foundation

/// 收藏位置與收藏路線清單上的「國家 · 城市」:快取鍵、Nominatim 請求、回應 → 標籤的純函式,
/// 照 Android `RegionLookup.key` 與 `GeocoderRepository.reverseRegion`(GFlyer-Suite
/// docs/features/region-labels.md §3.2、§3.4、§3.5;對照 fixture `region/nominatim-labels.json`)。
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

/// 收藏位置與收藏路線第一點的「國家 · 城市」反查佇列與本機快取,照 Android `data/RegionLookup.kt`
/// (GFlyer-Suite docs/features/region-labels.md §3.1、§3.3、§3.6、§3.7)。由 `SimulationController` 持有。
///
/// - Nominatim 的規範是每秒最多一次請求:同一時間只有一個請求,依排入的順序處理;每次真的送出請求之後
///   (成功或失敗)等 1.1 秒才處理下一筆。已經有快取而跳過的不等,第一筆也不等。
/// - 已經有快取、這次執行排過隊、這次執行失敗過的快取鍵一律跳過,所以同一格只送第一個排進來的座標,
///   呼叫端很頻繁地送同一份清單也不會多送請求。
/// - 失敗不重試、不寫進快取,使用者也看不到任何訊息;下次啟動(新的 `SimulationController`)再試一次。
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
    /// 排隊中、還沒處理的座標。只在記憶體裡:App 結束時還沒查的,下次啟動會因為沒有快取再排進來。
    private var pending: [GeoCoordinate] = []
    /// 這次執行排過隊的鍵。只增不減:處理完的鍵不是進了快取就是進了 `failed`,效果相同(和 Android 一樣)。
    private var queued: Set<String> = []
    private var failed: Set<String> = []
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

    /// 這些座標的地區還沒查過就依序排進佇列;已知的、排過隊的、這次已失敗的都跳過。
    func request(_ coordinates: [GeoCoordinate]) {
        for coordinate in coordinates {
            let key = RegionLabel.key(for: coordinate)
            guard labels[key] == nil, !queued.contains(key), !failed.contains(key) else { continue }
            queued.insert(key)
            pending.append(coordinate)
        }
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await drain()
        }
    }

    /// 等佇列處理完。App 不需要等,給測試用。
    func waitUntilIdle() async {
        if let worker { await worker.value }
    }

    /// 單一工作依序處理佇列。整段在主執行緒上,只有等網路與等間隔時讓出,所以 `request` 在處理途中
    /// 加進來的座標會接在後面;佇列清空時的最後一次等待也已經等完,之後再開始的工作不會太早送出。
    private func drain() async {
        while !pending.isEmpty {
            let coordinate = pending.removeFirst()
            let key = RegionLabel.key(for: coordinate)
            if labels[key] != nil { continue }
            guard let request = RegionLabel.request(for: coordinate, userAgent: userAgent) else {
                failed.insert(key)
                continue
            }
            let response = await transport.response(for: request)
            if let label = RegionLabel.label(status: response?.statusCode, body: response?.body) {
                labels[key] = label
                persist()
                onLabelsChange?(labels)
            } else {
                failed.insert(key)
            }
            await clock.sleep(seconds: Self.requestIntervalSeconds)
        }
        worker = nil
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
