import Foundation

extension String {
    /// 取前 `limit` 個 Unicode code point。
    ///
    /// 名稱的長度上限一律以 code point 為單位(GFlyer-Suite docs/DRIFT.md D14、
    /// contracts/fixtures/text/truncate-names.json),和 Android 的 `takeCodePoints`、
    /// JSON Schema 的 `maxLength` 一致。`prefix(n)` 以字素(grapheme)計算,國旗、
    /// 組合字元的結果會和 Android 不同,所以名稱上限不要用它。
    func prefixCodePoints(_ limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(String.UnicodeScalarView(unicodeScalars.prefix(limit)))
    }

    /// 超過 `limit` 個 code point 時回傳截斷後的字串,沒超過時是 nil。給輸入框的 `onChange` 用:
    /// 只有真的超過時才改寫綁定的值。留言板的輸入框上限也以 code point 計算
    /// (GFlyer-Suite docs/features/message-board-limits.md)。
    func codePointsCapped(at limit: Int) -> String? {
        unicodeScalars.count > limit ? prefixCodePoints(limit) : nil
    }
}
