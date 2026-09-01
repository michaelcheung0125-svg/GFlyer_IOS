import Foundation

/// 座標圖鑑資料來源：本機快取 → 線上（GFlyer-updates Pages）。
/// 以 JSON 內的 revision 判斷新舊，抓取失敗時退回最後一份可用資料。
/// 與 Android 不同，iOS 不內建種子資料；第一次使用需要網路下載。
actor CoordinateLibraryRepository {
    static let maxLibraryBytes = 4 * 1024 * 1024

    nonisolated let isConfigured: Bool
    private let remoteURL: URL?
    private let session: URLSession
    private let cacheFileURL: URL
    private var current: CoordinateLibrary?

    init(
        urlString: String = Bundle.main.object(forInfoDictionaryKey: "GFlyerCoordinateLibraryURL") as? String ?? "",
        session: URLSession = .shared,
        cacheDirectory: URL? = nil
    ) {
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: normalized),
           url.scheme?.lowercased() == "https",
           url.host?.isEmpty == false,
           url.user == nil,
           url.password == nil {
            remoteURL = url
            isConfigured = true
        } else {
            remoteURL = nil
            isConfigured = false
        }
        self.session = session
        let directory = cacheDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoordinateLibrary", isDirectory: true)
        cacheFileURL = directory.appendingPathComponent("coordinate_library.json")
    }

    /// 目前生效的資料；記憶體優先，其次本機快取，兩者皆無時回傳 nil。
    func load() -> CoordinateLibrary? {
        if let current { return current }
        guard let data = try? Data(contentsOf: cacheFileURL),
              let library = try? CoordinateLibrary.parse(data) else { return nil }
        current = library
        return library
    }

    /// 抓線上版；只有 revision 較新且解析成功才會取代並寫入快取。
    func refresh() async throws -> CoordinateLibrary {
        let baseline = load()
        guard let remoteURL else {
            if let baseline { return baseline }
            throw LibraryFormatError(message: "尚未設定座標庫網址。")
        }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GFlyer (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LibraryFormatError(message: "座標庫伺服器沒有傳回有效回應。")
        }
        guard (200...299).contains(http.statusCode) else {
            throw LibraryFormatError(message: "座標庫伺服器傳回錯誤：HTTP \(http.statusCode)。")
        }
        guard data.count <= Self.maxLibraryBytes else {
            throw LibraryFormatError(message: "座標庫資料檔案過大。")
        }
        let library = try CoordinateLibrary.parse(data)
        if let baseline, library.revision <= baseline.revision { return baseline }
        try? FileManager.default.createDirectory(
            at: cacheFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL, options: .atomic)
        current = library
        return library
    }
}
