import SwiftUI

// 這個檔案是 UI/ 底下樣式數值的單一來源。
//
// 會有這一層，是因為盤點時 UI/ 的七個檔案裡散著 247 處樣式 call site：
// 光是間距就用掉了 2 到 12 之間的每一個整數，而且沒有任何一個地方能一次
// 改動它們。token 的目的不是讓畫面更好看，是讓下一次調整只需要改這個檔。
//
// 兩條界線，加東西進來之前先確認：
//
// 1. 顏色一律包 SwiftUI 的語意色，不寫死 hex。系統色會自己在淺色與深色
//    之間切換（例如 orange 是 #FF9500 / #FF9F0A），寫死 hex 就會把這個
//    免費的深色模式支援弄丟——而專案現有的 64 處 .secondary 和 7 處
//    .primary 靠的正是同一套機制。token 只負責取名字，不改值。
//
// 2. 只出現一次、而且預期不會再出現第二次的數值不要放進來。那不是 token，
//    是那個 view 自己的細節，留在原地比較好讀。速度讀數的 78pt 寬、
//    機場助理輸入框的 190pt 寬都屬於這一類，刻意沒有收進來。

// MARK: - 間距

/// 四階間距尺度，取代原本散落的 2/3/4/5/6/7/8/9/10/11/12。
///
/// 值取自「緊湊」方案。整體會比現況略緊——原本用得最多的 `spacing: 4`
/// 會收到 2，`spacing: 8` 會收到 6——這是在 token 預覽頁上左右對照過
/// 之後選定的，不是估的。
enum Spacing {
    /// 2pt。同一組文字的行與行、工具列按鈕彼此之間。
    static let xs: CGFloat = 2
    /// 6pt。圖示與它的文字、清單的列與列。
    static let sm: CGFloat = 6
    /// 10pt。控制面板的列距、並排按鈕之間。
    static let md: CGFloat = 10
    /// 14pt。卡片內距、區塊與區塊之間。
    static let lg: CGFloat = 14
}

// MARK: - 版面座標

/// 不屬於間距尺度的固定位置與尺寸。
///
/// 這些是「這個元件要放在哪、要多大」，不是「兩個東西之間留多少」。
/// 混進 `Spacing` 會讓兩邊都不好改：調間距尺度時不該動到搖桿的位置，
/// 調搖桿位置時也不該牽動整個 App 的疏密。
enum Layout {
    /// 搖桿盤的直徑。
    static let joystickDiameter: CGFloat = 132
    /// 搖桿盤距離畫面左緣。
    static let joystickLeadingInset: CGFloat = 18
    /// 控制面板展開時，搖桿盤要讓開的高度。
    static let joystickBottomInsetPanelExpanded: CGFloat = 258
    /// 控制面板收合時，搖桿盤要讓開的高度。
    static let joystickBottomInsetPanelCollapsed: CGFloat = 120
    /// 操作提示膠囊距離畫面上緣，數值要讓它落在搜尋列底下。
    static let feedbackToastTopInset: CGFloat = 84
    /// 搜尋結果清單的最大高度，超過就讓它自己捲。
    static let searchResultsMaxHeight: CGFloat = 240
}

// MARK: - 度量

enum Metrics {
    /// 可點目標的最小邊長。
    ///
    /// 44pt 是 Apple HIG 的下限，不是偏好。地圖工具列目前是 40×40，
    /// 改過來會讓那排按鈕變大一點——這是唯一會改變外觀的一項，要實機看過。
    static let tapTarget: CGFloat = 44
    /// 卡片與按鈕的圓角。現況十處用 8，另有 4 和 5 各一處是例外。
    static let corner: CGFloat = 8
    /// 狀態圓點的直徑。
    static let statusDot: CGFloat = 10
}

// MARK: - 動態

/// 動畫語彙。現況是 `.snappy` 與 `.easeOut(duration: 0.18)` 並存，
/// 收進來是為了下次要調整手感時只有一個地方要改。
enum Motion {
    /// 控制面板與地圖工具列的展開收合。
    static let panel: Animation = .snappy
    /// 操作提示出現。
    static let feedbackIn: Animation = .easeOut(duration: 0.18)
    /// 操作提示消失。
    static let feedbackOut: Animation = .easeIn(duration: 0.18)
    /// 按壓回饋。要比其他動畫都短——慢一點就不像「有反應」，而像播了一段動畫。
    static let tap: Animation = .easeOut(duration: 0.12)
}

// MARK: - 顏色

/// 狀態色。這五個名字描述的是「這個東西現在是什麼狀態」，
/// 不是「它是什麼顏色」——所以換掉底下的值時，語意不會跟著跑掉。
extension Color {
    /// 需要使用者注意，但還不是錯誤：連線中斷、需要開啟機場模式、
    /// 模擬已暫停、置頂貼文、待確認的步數記錄。
    static let statusAttention = Color.orange
    /// 正常或已完成：步驟完成、錄製進行中、邀請仍有效、已確認的步數記錄。
    static let statusOK = Color.green
    /// 目前所在或正在進行：目前位置圓點、目前步驟、搖桿。
    static let statusActive = Color.blue
    /// 危險或已失效：停止按鈕、已撤銷的邀請、失敗的步數記錄。
    static let statusDanger = Color.red
    /// 已收藏。
    static let statusFavorite = Color.yellow
}

/// 地圖資料色。
///
/// 和狀態色分開是有具體理由的：`routeStroke` 現在的值和 `statusAttention`
/// 一樣都是 orange，但它們表達的是兩件事。綁在一起的話，哪天要換警示色，
/// 地圖上的路線會跟著一起變色。兩個名字各自獨立，改一邊不會動到另一邊。
extension Color {
    /// 主路線的線條與路線點。
    static let routeStroke = Color.orange
    /// 次要路線的虛線。
    static let routeAlternate = Color.purple
}

// MARK: - 字體

/// 重複出現的字體組合。
///
/// 刻意不自訂字級：現況 93 處字體有 92 處用的是語意字級（`.caption`、
/// `.subheadline` 之類），Dynamic Type 因此本來就會自動生效。這裡只是把
/// 重複寫了好幾次的組合取個名字，語意字級本身不動。
extension Font {
    /// 列標題與強調標籤。原本寫作 `.subheadline.weight(.semibold)`，七處。
    static let labelEmphasis = Font.subheadline.weight(.semibold)
    /// 會逐格跳動的數字，等寬數字避免抖動。
    /// 原本寫作 `.caption.monospacedDigit()`，七處。
    static let numericCaption = Font.caption.monospacedDigit()
    /// 同上，用在比較顯著的位置。
    static let numericLabel = Font.subheadline.monospacedDigit()
}
