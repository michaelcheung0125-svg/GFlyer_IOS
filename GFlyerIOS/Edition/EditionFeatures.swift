/// 親友版和公開版不同的地方。
///
/// 每個版本的資料夾（`GFlyerIOS/Family/`、`GFlyerIOS/Public/`）各有一個
/// `enum Edition: EditionFeatures`，兩個 App target 各自只編譯其中一個，所以共用的
/// 程式直接寫 `Edition.xxx`。這個 protocol 保證兩個版本有相同的成員：哪個版本少了
/// 一項，那個版本就編譯不過。照 Android 每個版本的 `object Edition`
/// （GFlyer 的 `app/src/<版本>/java/com/geopilot/app/edition/Edition.kt`）。
///
/// 共用的程式只經這裏碰版本專屬的東西（docs/APP_STORE_PLAN.md 第 8 項）。
protocol EditionFeatures {
    /// 捷徑和 LocalDevVPN 回到 App 用的自訂 scheme，要和這個版本 `Info.plist` 的
    /// `CFBundleURLTypes` 一致。兩個版本不可以相同：兩個 App 都裝了的話，iOS 不保證
    /// 回呼打開的是哪一個。
    static var callbackScheme: String { get }
}
