import Foundation

/// App 內「開放原始碼授權」頁的資料（docs/APP_STORE_PLAN.md 第 18 項，GFlyer-Suite DRIFT D34）。
///
/// 不是手寫的：`scripts/open_source_licenses.py` 從 idevice 釘住的 revision 產生 `Resources/OpenSourceLicenses.json`，
/// 列出 `libidevice_ffi.a` 實際連結的 Rust 套件和 Rust 標準程式庫，附上各自的授權全文；CI 的「Open source licences」
/// 核對它和連結的相符。兩個版本打包的第三方程式相同，所以共用一份。
struct OpenSourceLicenses: Decodable, Equatable {
    struct Library: Decodable, Equatable, Identifiable {
        let name: String
        /// Rust 標準程式庫跟着編譯器，沒有版本，是空字串。
        let version: String
        /// Cargo.toml 的 license，例如 `MIT OR Apache-2.0`。
        let license: String
        /// 套件附的全文（NOTICE 在前），`text` 是 `OpenSourceLicenses.texts` 的鍵。
        let texts: [TextReference]

        var id: String { "\(name) \(version)" }

        /// 清單上名稱底下的一行：版本和授權。
        var summary: String { version.isEmpty ? license : "\(version)\n\(license)" }
    }

    struct TextReference: Decodable, Equatable {
        let title: String
        let text: String
    }

    /// 按名稱排好。
    let libraries: [Library]
    /// 全文，相同的只放一份。
    let texts: [String: String]

    static let resourceName = "OpenSourceLicenses"

    static func load(bundle: Bundle = .main) throws -> OpenSourceLicenses {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> OpenSourceLicenses {
        try JSONDecoder().decode(OpenSourceLicenses.self, from: data)
    }

    func fullText(_ reference: TextReference) -> String? {
        texts[reference.text]
    }

    /// 全文分成段落（空行分開），很長的全文可以逐段畫。段落裏的換行和縮排照原樣保留：授權全文常有排好的清單和框線。
    /// 和 Android 的 `OpenSourceLicenses.paragraphs` 相同。
    static func paragraphs(_ text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var paragraphs: [String] = []
        var current: [Substring] = []

        func finish() {
            let kept = current.drop(while: { $0.allSatisfy(\.isWhitespace) })
            var paragraph = kept.joined(separator: "\n")
            while paragraph.last?.isWhitespace == true { paragraph.removeLast() }
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            current = []
        }

        for line in lines {
            // 只有空格和 tab 的一行算空行
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
                finish()
            } else {
                current.append(line)
            }
        }
        finish()
        return paragraphs
    }
}

/// 「開放原始碼授權」頁和設定頁入口的字。頁名和入口照 Android；iOS 沒有第三方的圖示（圖示是 SF Symbols 和
/// JetPiggy 自己的飛豬），所以說明只寫程式庫，Android 是「程式庫和圖示」「程式庫和素材」。
enum OpenSourceLicensesText {
    static let title = "開放原始碼授權"
    static let entrySubtitle = "App 用到的程式庫的授權"
    static let intro = "這個 App 用到下列開放原始碼程式庫。點一項可以看授權全文。"
    static let loadFailed = "讀不到授權清單"
    static let textLoadFailed = "讀不到授權全文"

    static func librariesSection(count: Int) -> String {
        "程式庫（\(count)）"
    }
}
