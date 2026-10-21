import Foundation

/// 親友版的「國家 · 城市」反查:送去 OpenStreetMap 的 Nominatim,照 Android 親友版的 `NominatimGeocoder.reverseRegion`
/// (GFlyer-Suite docs/features/region-labels.md §3.4、§3.5;對照 fixture `region/nominatim-labels.json`)。
/// 公開版不連 Nominatim(公開的 Nominatim 只准全部用戶合計每秒一次),改用 Apple 的地點服務(DRIFT D33)。
struct NominatimRegionLabelSource: RegionLabelSource {
    let transport: any RegionLookupTransport
    let userAgent: String

    init(
        transport: any RegionLookupTransport = URLSessionRegionLookupTransport(),
        userAgent: String = RegionLabel.userAgent()
    ) {
        self.transport = transport
        self.userAgent = userAgent
    }

    func label(for coordinate: GeoCoordinate) async -> String? {
        guard let request = RegionLabel.request(for: coordinate, userAgent: userAgent) else { return nil }
        let response = await transport.response(for: request)
        return RegionLabel.label(status: response?.statusCode, body: response?.body)
    }
}

extension RegionLabel {
    /// 城市依序取第一個不是空白的欄位。其他欄位一律不看,包括日本、中國、荷蘭的省級常用的 `province`。
    static let cityFields = ["city", "town", "municipality", "village", "county", "state_district", "state"]
    /// Android 是連線 8 秒、讀取 8 秒;`URLRequest` 只有一個閒置逾時,兩段都受它限制。
    static let timeoutSeconds: TimeInterval = 8

    /// `GFlyer/<版本> (iOS; +gflyer@jetpiggy.com)`。Nominatim 的規範要求能辨識 App、最好附上聯絡方式,
    /// 不能用 URLSession 預設的 User-Agent。Android 是 `GFlyer/<版本> (+gflyer@jetpiggy.com)`
    /// (GFlyer-Suite docs/features/region-labels.md 3.4)。
    static func userAgent(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "GFlyer/\(version) (iOS; +\(ContactEmail.address))"
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
        let country = nonBlank(address["country"] as? String)
        let city = cityFields.compactMap { nonBlank(address[$0] as? String) }.first
        return join(country: country, city: city)
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
