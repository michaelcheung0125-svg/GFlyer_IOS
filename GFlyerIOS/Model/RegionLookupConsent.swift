import Foundation

/// 自動反查收藏的「國家 · 城市」要不要先取得同意,照 Android `model/RegionLookupConsent.kt`
/// (GFlyer-Suite docs/features/region-labels.md 3.10)。只有要先問的版本(公開版)用得到:開 App 就把收藏的座標
/// 送出去,不是使用者按了才發生的。Android 公開版因為 Play 的 User Data 政策先問,iOS 公開版照着做,
/// 兩個平台的公開版一致(docs/APP_STORE_PLAN.md 的 U7)。不用問的版本(親友版)一律當成允許。
/// 答案只存在這部手機上,不放進備份檔(`RegionLookup.consentStorageKey`)。
enum RegionLookupConsent: String {
    case unasked
    case allowed
    case declined
}

/// 誰叫出同意的說明:開 App 或收藏變動時有座標要查、按 ☆、或在設定打開開關。
enum RegionConsentPrompt: Equatable {
    case lookup
    case star
    case settings
}

enum RegionLookupConsentRules {
    /// 可以送出反查、顯示標籤、按 ☆ 時預填地名。
    static func lookupsAllowed(asksFirst: Bool, consent: RegionLookupConsent) -> Bool {
        !asksFirst || consent == .allowed
    }

    /// 開 App 或收藏變動時:要先問、還沒答過,而且真的有座標要查,才跳出說明。
    static func asksOnLookup(asksFirst: Bool, consent: RegionLookupConsent, coordinateCount: Int) -> Bool {
        asksFirst && consent == .unasked && coordinateCount > 0
    }

    /// 按 ☆ 時:要先問、還沒答過,就先跳出說明,答完才打開命名 sheet。
    static func asksOnStar(asksFirst: Bool, consent: RegionLookupConsent) -> Bool {
        asksFirst && consent == .unasked
    }
}

/// 同意說明和設定開關的文字,和 Android 公開版一字不差;只有服務名稱跟着版本
/// (Android `RegionLookupConsentText` 和 `PlaceLookupPrivacy`)。
enum RegionLookupConsentText {
    static let title = "顯示收藏的國家與城市？"
    static let allowButton = "允許"
    static let declineButton = "不用"
    static let settingTitle = "顯示收藏的國家與城市"
    /// 設定裏放這個開關的那一組;說明叫使用者到這裏改。
    static let settingsGroupTitle = "提示與地名"

    /// 同意說明的內文,兩段。`service` 是反查送去的服務(`Edition.regionLookupConsentService`)。
    static func paragraphs(service: String) -> [String] {
        [
            "收藏清單可以在每個收藏旁邊顯示所在的國家與城市，例如「臺灣 · 臺北市」。要查出來，收藏位置與收藏路線第一點的座標會送往\(spaced(service))；之後按 ☆ 收藏新的地點時，那一點的座標也會立刻送出，用來預先填入名稱。",
            "查到的結果只存在本機，不會放進備份檔。不允許也可以照常收藏，只是不顯示國家與城市。之後可以在設定的「\(settingsGroupTitle)」更改。",
        ]
    }

    /// 設定開關底下的一行。
    static func settingDescription(service: String) -> String {
        "收藏的座標會送往\(spaced(service))查詢"
    }

    /// 名稱是英文開頭時前面空一格,和其他的字一樣中英文之間空一格。
    private static func spaced(_ name: String) -> String {
        guard let first = name.unicodeScalars.first, first.isASCII else { return name }
        return " " + name
    }
}
