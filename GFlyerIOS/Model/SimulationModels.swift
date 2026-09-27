import Foundation

enum SimulationMode: String, CaseIterable, Identifiable, Codable {
    case teleport = "傳送"
    case singleRoute = "單點"
    case multiRoute = "多點"
    case explore = "探索"

    var id: Self { self }

    var isRoute: Bool {
        self == .singleRoute || self == .multiRoute
    }
}

enum LoopTransitionMode: String, CaseIterable, Identifiable, Codable {
    case walkBack = "走回起點"
    case teleportToStart = "直接返回"

    var id: Self { self }

    /// 畫面上的名稱,和 Android 相同。rawValue 是中斷恢復快照裡存的值,不能跟著改。
    var label: String {
        switch self {
        case .walkBack: return "走回起點"
        case .teleportToStart: return "瞬間跳轉"
        }
    }
}

// 下面兩個 enum 的 rawValue 是 `PlaybackSettings` 存檔裡的值:把「逐點傳送」改成「定點傳送」會讓
// 舊資料解不出來而退回模擬移動。畫面上的名稱用 `label`(GFlyer-Suite
// docs/features/route-arrival-actions.md I1)。

enum RouteTravelMode: String, CaseIterable, Identifiable, Codable {
    case simulate = "模擬移動"
    case teleport = "逐點傳送"

    var id: Self { self }

    var label: String {
        switch self {
        case .simulate: return "模擬移動"
        case .teleport: return "定點傳送"
        }
    }
}

enum RoutePointAction: String, CaseIterable, Identifiable, Codable {
    case none = "無"
    case orbit = "繞圈"
    case microMove = "微動"

    var id: Self { self }

    /// 選得到的到點動作,和 Android 相同。`none` 只剩 0.6.8 以前「定點傳送 + 無動作」的舊資料:
    /// 照舊執行(到點不做動作),但選不到,也沒有顯示名稱。
    static let selectableCases: [RoutePointAction] = [.orbit, .microMove]

    var label: String? {
        switch self {
        case .none: return nil
        case .orbit: return "繞圈"
        case .microMove: return "向東走 20 米"
        }
    }
}

struct PlaybackSettings: Codable, Equatable {
    static let dwellRange = 1...300
    static let orbitRadiusRange = 5...500
    static let orbitRadiusStepMetres = 5
    static let maxOrbitLaps = 4
    static let defaultOrbitRadiiMetres = [20, 30]
    /// 設定頁「新增一圈」的半徑。
    static let addedLapRadiusMetres = 40
    static let startDelayOptions = [0, 3, 5, 10]
    static let autoStopOptions = [0, 30, 60, 120]
    static let microMoveDistanceMetres = 20.0
    static let joystickMaxSpeedOptions = [20, 60, 150, 500, 900]
    static let joystickMaxSpeedRange = 5...900
    /// 到點規則的版本。2 是 0.6.9 起和 Android 相同的規則:到點動作、手動前進與停留只在定點傳送使用。
    static let currentArrivalRulesVersion = 2

    var travelMode: RouteTravelMode = .simulate
    var pointAction: RoutePointAction = .orbit
    var manualAdvance = false
    var dwellSeconds = 10
    var orbitRadiiMetres = defaultOrbitRadiiMetres
    var startDelaySeconds = 0
    var autoStopMinutes = 0
    var crossDateWarningEnabled = true
    var joystickMaxSpeedKilometresPerHour = 500
    /// 新安裝就是目前的版本;0.6.8 以前存的資料沒有這個鍵,解碼成 1,載入時遷移一次
    /// (`migratedToArrivalRulesV2`)。存檔裡分不出「選了無動作」和「沒動過預設值」,只能靠它。
    var arrivalRulesVersion = currentArrivalRulesVersion
    /// 遷移時設定、按「知道了」後清掉的一次性提示(`SimulationController.arrivalRulesNoticeMessage`)。
    var pendingArrivalRulesNotice = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case travelMode, pointAction, manualAdvance, dwellSeconds
        case orbitRadiiMetres, startDelaySeconds, autoStopMinutes, crossDateWarningEnabled
        case joystickMaxSpeedKilometresPerHour
        case arrivalRulesVersion, pendingArrivalRulesNotice
    }

    // 缺欄位或型別不符時退回屬性宣告上的預設值（單一定義處）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = PlaybackSettings()
        settings.travelMode = (try? container.decode(RouteTravelMode.self, forKey: .travelMode)) ?? settings.travelMode
        settings.pointAction = (try? container.decode(RoutePointAction.self, forKey: .pointAction)) ?? settings.pointAction
        settings.manualAdvance = (try? container.decode(Bool.self, forKey: .manualAdvance)) ?? settings.manualAdvance
        settings.dwellSeconds = (try? container.decode(Int.self, forKey: .dwellSeconds)) ?? settings.dwellSeconds
        settings.orbitRadiiMetres = (try? container.decode([Int].self, forKey: .orbitRadiiMetres)) ?? settings.orbitRadiiMetres
        settings.startDelaySeconds = (try? container.decode(Int.self, forKey: .startDelaySeconds)) ?? settings.startDelaySeconds
        settings.autoStopMinutes = (try? container.decode(Int.self, forKey: .autoStopMinutes)) ?? settings.autoStopMinutes
        settings.crossDateWarningEnabled =
            (try? container.decode(Bool.self, forKey: .crossDateWarningEnabled)) ?? settings.crossDateWarningEnabled
        settings.joystickMaxSpeedKilometresPerHour =
            (try? container.decode(Int.self, forKey: .joystickMaxSpeedKilometresPerHour))
            ?? settings.joystickMaxSpeedKilometresPerHour
        // 沒有這個鍵就是 0.6.8 以前的資料,不是新安裝:用 1 而不是屬性上的預設值
        settings.arrivalRulesVersion = (try? container.decode(Int.self, forKey: .arrivalRulesVersion)) ?? 1
        settings.pendingArrivalRulesNotice =
            (try? container.decode(Bool.self, forKey: .pendingArrivalRulesNotice)) ?? settings.pendingArrivalRulesNotice
        self = settings.sanitized()
    }

    // 每次存檔都會跑,所以只放「對任何值重做都不變」的整理。到點規則的遷移不能放這裡,
    // 否則版本 2 的「模擬移動 + 無動作」每存一次都會被改成繞圈。
    func sanitized() -> PlaybackSettings {
        var copy = self
        copy.dwellSeconds = Self.clampedDwellSeconds(dwellSeconds)
        copy.orbitRadiiMetres = Self.normalizedOrbitRadii(orbitRadiiMetres)
        // 非選項值（例如 Android 備份帶來的 15 分鐘）取最接近的選項而不是直接停用
        copy.startDelaySeconds = Self.nearestOption(to: startDelaySeconds, in: Self.startDelayOptions)
        copy.autoStopMinutes = Self.nearestAutoStopOption(to: autoStopMinutes)
        copy.joystickMaxSpeedKilometresPerHour = min(
            max(joystickMaxSpeedKilometresPerHour, Self.joystickMaxSpeedRange.lowerBound),
            Self.joystickMaxSpeedRange.upperBound
        )
        return copy
    }

    /// 0.6.8 以前的設定(版本 1)換成 0.6.9 的到點規則,和 Android 一致(GFlyer-Suite
    /// docs/features/route-arrival-actions.md §5.3)。由 `LocalDataStore` 載入時呼叫;版本已經是 2
    /// 時原樣回傳,所以可以重複呼叫。
    /// - 模擬移動 + 無動作 → 繞圈:現在沒有差別,之後切到定點傳送時預先選好 Android 的預設。
    /// - 定點傳送 + 無動作 → 保留:照舊傳送、停留、下一點,兩個選項都不選取(Q1)。
    /// - 模擬移動 + 繞圈/微動,或勾了手動前進:值保留,但模擬移動不再執行它們,所以標記一次性提示(Q2)。
    /// 停留 0 → 1 與半徑去重由 `sanitized()` 負責(解碼時已經做過)。
    func migratedToArrivalRulesV2() -> PlaybackSettings {
        guard arrivalRulesVersion < 2 else { return self }
        var copy = self
        if travelMode == .simulate {
            if pointAction != .none || manualAdvance { copy.pendingArrivalRulesNotice = true }
            if pointAction == .none { copy.pointAction = .orbit }
        }
        copy.arrivalRulesVersion = 2
        return copy
    }

    /// 傳送到點停留夾到 1〜300 秒,和 Android 相同(contracts/fixtures/route/arrival-actions.json 的
    /// dwellSeconds)。舊版 iOS 允許 0,讀進來變成 1。
    static func clampedDwellSeconds(_ seconds: Int) -> Int {
        min(max(seconds, dwellRange.lowerBound), dwellRange.upperBound)
    }

    /// 繞圈半徑的整理,和 Android 相同(fixture 的 orbitRadii):只留 5〜500 的值(範圍外丟掉,不夾限)
    /// → 去除重複、保留第一次出現的位置 → 取前 4 個 → 空的用 [20, 30]。
    static func normalizedOrbitRadii(_ radii: [Int]) -> [Int] {
        var kept: [Int] = []
        for radius in radii where orbitRadiusRange.contains(radius) && !kept.contains(radius) {
            kept.append(radius)
        }
        let laps = Array(kept.prefix(maxOrbitLaps))
        return laps.isEmpty ? defaultOrbitRadiiMetres : laps
    }

    enum OrbitRadiusEdit: Equatable {
        case decrease(index: Int)
        case increase(index: Int)
        case delete(index: Int)
        case add
    }

    /// 設定頁「繞圈設定」的一次編輯,改完再經過 `normalizedOrbitRadii`(fixture 的 orbitRadiiEdits)。
    /// 回傳 nil 表示那個按鈕不存在或停用:已經 4 圈時沒有「新增一圈」,只剩 1 圈時不能刪。
    /// 因為會去重,把某一圈調到和另一圈一樣時那一圈會消失,已經有 40 公尺時「新增一圈」沒有變化
    /// (規格 Q3,照 Android)。
    static func editedOrbitRadii(_ radii: [Int], _ edit: OrbitRadiusEdit) -> [Int]? {
        var edited = radii
        switch edit {
        case let .decrease(index):
            guard edited.indices.contains(index) else { return nil }
            edited[index] = max(edited[index] - orbitRadiusStepMetres, orbitRadiusRange.lowerBound)
        case let .increase(index):
            guard edited.indices.contains(index) else { return nil }
            edited[index] = min(edited[index] + orbitRadiusStepMetres, orbitRadiusRange.upperBound)
        case let .delete(index):
            guard edited.count > 1, edited.indices.contains(index) else { return nil }
            edited.remove(at: index)
        case .add:
            guard edited.count < maxOrbitLaps else { return nil }
            edited.append(addedLapRadiusMetres)
        }
        return normalizedOrbitRadii(edited)
    }

    /// 自動停止對齊到最近的選項,距離相同時取較大的:15 分鐘變成 30,而不是變成 0
    /// 把自動停止關掉。和 Android 的 `AutoStop.nearestOption` 相同(GFlyer-Suite
    /// docs/DRIFT.md D15、contracts/fixtures/settings/auto-stop-minutes.json)。
    static func nearestAutoStopOption(to minutes: Int) -> Int {
        nearestOption(to: minutes, in: autoStopOptions, preferLargerOnTie: true)
    }

    /// 距離相同時預設取較小的(`startDelaySeconds` 一直是這樣,它不是跨平台的設定)。
    private static func nearestOption(to value: Int, in options: [Int], preferLargerOnTie: Bool = false) -> Int {
        guard let lowest = options.min(), let highest = options.max() else { return 0 }
        // 先夾進選項範圍:範圍外最近的一定是端點,也避免極端值在 abs 裡溢位而當掉
        let value = min(max(value, lowest), highest)
        return options.min { lhs, rhs in
            let lhsDistance = abs(lhs - value)
            let rhsDistance = abs(rhs - value)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return preferLargerOnTie && lhs > rhs
        } ?? 0
    }
}

/// 到點繞圈,和 Android `MockLocationService.orbitAround` 相同(contracts/fixtures/route/arrival-actions.json
/// 的 orbit):每個半徑一圈,從正東(角度 0)開始逆時針轉;每一步先 angle += stepRadians 再發送
/// offset(路線點, r·cos, r·sin)。換下一圈時角度不歸零,接著累加。
enum OrbitPlanner {
    struct Lap: Equatable {
        let radiusMetres: Int
        let stepRadians: Double
        let waypoints: [GeoCoordinate]
        /// 最後一步的角度,下一圈從這裡接著轉。
        let endAngleRadians: Double
    }

    /// 一圈的每一步。播放時每一圈開始才呼叫,所以播放中改了速度,下一圈開始生效。
    static func lap(
        center: GeoCoordinate,
        radiusMetres: Int,
        startAngleRadians: Double,
        speedMetresPerSecond: Double,
        tickSeconds: Double
    ) -> Lap {
        let radius = Double(radiusMetres)
        let step = stepRadians(speedMetresPerSecond: speedMetresPerSecond, radiusMetres: radius, tickSeconds: tickSeconds)
        let steps = stepsPerLap(stepRadians: step)
        var angle = startAngleRadians
        var waypoints: [GeoCoordinate] = []
        waypoints.reserveCapacity(steps)
        for _ in 0..<steps {
            angle += step
            waypoints.append(
                GeoMath.offset(from: center, eastMetres: radius * cos(angle), northMetres: radius * sin(angle))
            )
        }
        return Lap(radiusMetres: radiusMetres, stepRadians: step, waypoints: waypoints, endAngleRadians: angle)
    }

    /// 整段繞圈在速度不變時的結果(測試用;播放時逐圈呼叫 `lap`)。
    static func laps(
        center: GeoCoordinate,
        radiiMetres: [Int],
        speedMetresPerSecond: Double,
        tickSeconds: Double
    ) -> [Lap] {
        var angle = 0.0
        var laps: [Lap] = []
        for radius in radiiMetres {
            let next = lap(
                center: center,
                radiusMetres: radius,
                startAngleRadians: angle,
                speedMetresPerSecond: speedMetresPerSecond,
                tickSeconds: tickSeconds
            )
            angle = next.endAngleRadians
            laps.append(next)
        }
        return laps
    }

    static func stepRadians(speedMetresPerSecond: Double, radiusMetres: Double, tickSeconds: Double) -> Double {
        max(speedMetresPerSecond, 0.1) / max(radiusMetres, 1) * tickSeconds
    }

    static func stepsPerLap(stepRadians: Double) -> Int {
        max(Int(ceil(2 * Double.pi / max(stepRadians, 1e-9))), 8)
    }

    static func stepsPerLap(speedMetresPerSecond: Double, radiusMetres: Double, tickSeconds: Double) -> Int {
        stepsPerLap(
            stepRadians: stepRadians(
                speedMetresPerSecond: speedMetresPerSecond,
                radiusMetres: radiusMetres,
                tickSeconds: tickSeconds
            )
        )
    }
}

struct QuickSpeedPreset: Codable, Equatable, Identifiable {
    /// 新增與匯入備份的上限。和 Android 統一為 6 個(GFlyer-Suite docs/DRIFT.md D2)。
    static let maxCount = 6

    /// 儲存時的上限。舊版允許 12 個,已經存了超過 6 個的使用者原本的預設全部保留,
    /// 只是不能再新增;存檔時若改用 maxCount 截斷,刪掉 1 個會連帶少掉好幾個。
    static let legacyMaxStoredCount = 12

    /// 名稱最多 20 個 Unicode code point,和 Android 相同(DRIFT D14)。
    static let maxNameLength = 20

    let id: UUID
    var name: String
    var kilometresPerHour: Double

    init(id: UUID = UUID(), name: String, kilometresPerHour: Double) {
        self.id = id
        self.name = name
        self.kilometresPerHour = SpeedScale.clamped(kilometresPerHour)
    }

    /// 內建預設:名稱完全相同,速度相差不到 0.01 km/h。原本用 == 比速度,還原 Android 備份後
    /// 「正常走路」「腳踏車」「汽車」是 Float 放寬的值(例如 5.000000238 km/h),會被當成自訂
    /// 預設而出現刪除鈕(GFlyer-Suite contracts/fixtures/speed/preset-speed-values.json)。
    var isBuiltIn: Bool {
        SpeedScale.defaultPresets.contains {
            $0.name.unicodeScalars.elementsEqual(name.unicodeScalars)
                && SpeedScale.isSameSpeed($0.kilometresPerHour, kilometresPerHour)
        }
    }

    /// 舊版 Android 的「正常走路」(1.4 m/s = 5.04 km/h)換成目前的 5.0 km/h,id、名稱不變。
    /// 0.6.8 以前在 iOS 還原舊 Android 備份的人,裝置上存的就是 5.04。冪等:5.0 不在範圍內,
    /// 所以每次載入都跑也安全(contracts/fixtures/backup/legacy-walk-preset.json)。
    func replacingLegacyWalk() -> QuickSpeedPreset {
        guard SpeedScale.isLegacyWalk(name: name, metresPerSecond: kilometresPerHour / 3.6) else { return self }
        return QuickSpeedPreset(id: id, name: name, kilometresPerHour: SpeedScale.walkKilometresPerHour)
    }
}

struct SavedPlace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let coordinate: GeoCoordinate
    let createdAt: Date
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: GeoCoordinate,
        createdAt: Date = .now,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.folderID = folderID
    }

    /// 新增與改名時的收藏名稱:和路線名稱同一條規則(上限同樣是 80),GFlyer-Suite
    /// docs/features/name-limits.md 的 N2。讀取時不套用:舊資料原樣讀回,下一次改名才正規化。
    static func normalizedName(_ name: String) -> String {
        SavedRoute.normalizedName(name)
    }
}

extension SavedRoute {
    /// 儲存時的路線名稱:去掉前後空白、截斷到 80 個 code point,再去掉截斷後留在結尾的空白。
    /// `LocalDataStore.insertRoute` 用這個結果比對同名,產生名稱的地方也必須先經過它,否則
    /// 「檢查時不同名、存的時候變成同名」會無聲覆蓋既有路線。和 Android 的 `RouteNames` 相同。
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixCodePoints(80)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct FavoriteFolder: Codable, Equatable, Identifiable {
    /// 新增資料夾的上限,和 Android 相同;備份還原兩個平台也都只取前 30 個。
    static let maxCount = 30

    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct SavedRoute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let points: [GeoCoordinate]
    var loop: Bool
    let createdAt: Date
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        points: [GeoCoordinate],
        loop: Bool,
        createdAt: Date = .now,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.loop = loop
        self.createdAt = createdAt
        self.folderID = folderID
    }
}

struct RouteDraft: Codable, Equatable {
    var points: [GeoCoordinate]
    var loop: Bool
    /// 草稿屬於多點還是單點模式。0.6.4 起多點路線不再自動帶入起點，兩個點的
    /// 多點草稿不能再靠點數判斷。舊草稿沒有這個欄位（nil），照舊用點數判斷。
    var isMultiPoint: Bool?
}

struct SimulationStatus: Equatable {
    var isActive = false
    var isPaused = false
    var coordinate: GeoCoordinate?
    var mode: SimulationMode?
    var message = "預覽後端已就緒"
    var countdownRemaining: Int?
    var waitingManualAdvance = false
    var isOrbiting = false
    /// 路線正在播放(含倒數、停留與等「下一點」)。播完或停止後是 false,位置可能仍在模擬中。
    var isPlayingRoute = false
    var autoStopAt: Date?
}

struct PlaceSearchResult: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: GeoCoordinate
}

enum SimulationError: LocalizedError {
    case pairingFileRequired
    case backendUnavailable(String)
    case invalidAddress
    case connectionFailed(String)
    case developerDiskImage(String)
    case routeNeedsTwoPoints
    case exploreAlreadyActive

    var errorDescription: String? {
        switch self {
        case .pairingFileRequired:
            return "尚未匯入這部 iPhone 的 pairing file。"
        case let .backendUnavailable(message):
            return message
        case .invalidAddress:
            return "LocalDevVPN 目標 IP 無效。"
        case let .connectionFailed(message):
            return message
        case let .developerDiskImage(message):
            return message
        case .routeNeedsTwoPoints:
            return "路線至少需要兩個座標。"
        case .exploreAlreadyActive:
            return "探索已經在執行中。"
        }
    }
}

enum RoutePlan {
    /// 泛型是為了讓 `RouteArrivalPlan` 用同一條規則排出路線點的位置編號。
    static func traversalPoints<Point>(
        _ points: [Point],
        loop: Bool,
        transitionMode: LoopTransitionMode = .walkBack
    ) -> [Point] {
        if loop, points.count >= 2, transitionMode == .walkBack {
            return points + [points[0]]
        }
        return points
    }
}

enum SpeedScale {
    static let minimumKilometresPerHour = 1.8
    static let walkKilometresPerHour = 5.0
    static let runKilometresPerHour = 10.8
    static let bicycleKilometresPerHour = 19.0
    static let carKilometresPerHour = 50.0
    static let airplaneKilometresPerHour = 900.0
    static let maximumKilometresPerHour = airplaneKilometresPerHour
    static let flowerLimitKilometresPerHour = 20.0

    static let defaultPresets = [
        QuickSpeedPreset(name: "正常走路", kilometresPerHour: walkKilometresPerHour),
        QuickSpeedPreset(name: "跑步", kilometresPerHour: runKilometresPerHour),
        QuickSpeedPreset(name: "腳踏車", kilometresPerHour: bicycleKilometresPerHour),
        QuickSpeedPreset(name: "汽車", kilometresPerHour: carKilometresPerHour),
        QuickSpeedPreset(name: "飛機", kilometresPerHour: airplaneKilometresPerHour),
    ]

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimumKilometresPerHour), maximumKilometresPerHour)
    }

    static func toSliderPosition(_ speed: Double) -> Double {
        let value = clamped(speed)
        let carPosition = 2.0 / 3.0
        if value <= carKilometresPerHour {
            return ((value - minimumKilometresPerHour) / (carKilometresPerHour - minimumKilometresPerHour)) * carPosition
        }
        return carPosition + ((value - carKilometresPerHour) / (airplaneKilometresPerHour - carKilometresPerHour)) * (1 - carPosition)
    }

    static func fromSliderPosition(_ position: Double) -> Double {
        let normalized = min(max(position, 0), 1)
        let carPosition = 2.0 / 3.0
        if normalized <= carPosition {
            return minimumKilometresPerHour
                + (normalized / carPosition) * (carKilometresPerHour - minimumKilometresPerHour)
        }
        return carKilometresPerHour + ((normalized - carPosition) / (1 - carPosition)) * (airplaneKilometresPerHour - carKilometresPerHour)
    }

    // 速度的相等與門檻比較一律用 km/h 的 Double,容差 0.01 km/h,和 Android 相同
    // (GFlyer-Suite contracts/fixtures/speed/preset-speed-values.json)。Android 以 Float 存 m/s,
    // 同一個「20 km/h」在兩邊是不同的數字,直接用 == 或 > 比會出現「顯示 20.0 卻跳警告」。

    static let sameSpeedTolerance = 0.01

    static func isSameSpeed(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < sameSpeedTolerance
    }

    static func isBelow(_ speed: Double, _ threshold: Double) -> Bool {
        speed < threshold && !isSameSpeed(speed, threshold)
    }

    static func isAtMost(_ speed: Double, _ threshold: Double) -> Bool {
        speed <= threshold || isSameSpeed(speed, threshold)
    }

    static func exceedsFlowerLimit(_ speed: Double) -> Bool {
        !isAtMost(speed, flowerLimitKilometresPerHour)
    }

    /// Android 0.8.6 以前內建「正常走路」的速度。
    static let legacyWalkMetresPerSecond = 1.4

    /// 名稱完全等於「正常走路」(不去空白)而且和 1.4 m/s 相差不到 0.001;不看 id。
    /// 還原備份與載入本機資料共用這一條(contracts/fixtures/backup/legacy-walk-preset.json)。
    /// 名稱逐個 code point 比,和 Android 的 == 相同;String 的 == 會把正規等價的字當成相同。
    static func isLegacyWalk(name: String, metresPerSecond: Double) -> Bool {
        name.unicodeScalars.elementsEqual("正常走路".unicodeScalars)
            && abs(metresPerSecond - legacyWalkMetresPerSecond) < 0.001
    }
}

struct SpiralState: Equatable {
    var angleRadians = 0.0
}

struct SpiralStep {
    let state: SpiralState
    let coordinate: GeoCoordinate
}

enum SpiralPath {
    static let ringSpacingMetres = 1_000.0
    private static let radiusPerRadian = ringSpacingMetres / (2.0 * Double.pi)

    static func advance(
        center: GeoCoordinate,
        current: GeoCoordinate,
        state: SpiralState,
        distanceMetres: Double
    ) -> SpiralStep {
        let distance = max(distanceMetres, 0)
        let arcLengthPerRadian = radiusPerRadian * sqrt(1 + state.angleRadians * state.angleRadians)
        let nextAngle = state.angleRadians + distance / arcLengthPerRadian
        let radius = radiusPerRadian * nextAngle
        let next = GeoMath.destination(
            from: center,
            bearingDegrees: nextAngle.radiansToDegrees,
            distanceMetres: radius
        )
        _ = current
        return SpiralStep(state: SpiralState(angleRadians: nextAngle), coordinate: next)
    }

    static func preview(
        center: GeoCoordinate,
        current: GeoCoordinate,
        state: SpiralState,
        distanceMetres: Double = 5_000,
        segmentLengthMetres: Double = 40
    ) -> [GeoCoordinate] {
        guard distanceMetres > 0 else { return [current] }
        var points = [current]
        var nextState = state
        var nextCoordinate = current
        var remaining = distanceMetres
        while remaining > 0 {
            let step = advance(
                center: center,
                current: nextCoordinate,
                state: nextState,
                distanceMetres: min(segmentLengthMetres, remaining)
            )
            nextState = step.state
            nextCoordinate = step.coordinate
            points.append(nextCoordinate)
            remaining -= segmentLengthMetres
        }
        return points
    }
}

enum CooldownEstimator {
    static func estimateSeconds(distanceMetres: Double) -> Int {
        switch distanceMetres {
        case ..<1_000: return 30
        case ..<5_000: return 120
        case ..<10_000: return 300
        case ..<25_000: return 600
        case ..<100_000: return 1_800
        case ..<250_000: return 2_700
        case ..<500_000: return 3_600
        case ..<1_000_000: return 5_400
        default: return 7_200
        }
    }
}

private extension Double {
    var radiansToDegrees: Double { self * 180 / .pi }
}
