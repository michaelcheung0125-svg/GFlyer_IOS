import SwiftUI

/// 「開放原始碼授權」頁（docs/APP_STORE_PLAN.md 第 18 項）：App 打包的程式庫和它們的授權。照 Android 的
/// `OpenSourceLicensesPage`：說明、程式庫清單，點一項推進一頁全文。從設定頁「關於」推進來，兩個版本都有。
/// Android 的「程式庫內含的開放原始碼」（從 AAR 抽出）和「圖示」兩段 iOS 沒有東西可以列，所以沒有。
struct OpenSourceLicensesView: View {
    @State private var loaded: Result<OpenSourceLicenses, Error>?

    var body: some View {
        content
            .navigationTitle(OpenSourceLicensesText.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard loaded == nil else { return }
                // 清單連全文約半 MB，在背景讀
                loaded = await Task.detached { Result { try OpenSourceLicenses.load() } }.value
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loaded {
        case nil:
            ProgressView()
        case .some(.failure):
            message(OpenSourceLicensesText.loadFailed)
        case let .some(.success(licenses)):
            List {
                Section {
                    Text(OpenSourceLicensesText.intro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section(OpenSourceLicensesText.librariesSection(count: licenses.libraries.count)) {
                    ForEach(licenses.libraries) { library in
                        NavigationLink {
                            OpenSourceLicenseTextView(library: library, licenses: licenses)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(library.name)
                                Text(library.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一個程式庫的授權全文：版本和授權在最上面，每一份全文一段，段落照原樣用等寬字。
private struct OpenSourceLicenseTextView: View {
    let library: OpenSourceLicenses.Library
    let licenses: OpenSourceLicenses

    var body: some View {
        List {
            Section {
                Text(library.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(library.texts.enumerated()), id: \.offset) { _, reference in
                Section(reference.title) {
                    if let text = licenses.fullText(reference) {
                        ForEach(Array(OpenSourceLicenses.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        Text(OpenSourceLicensesText.textLoadFailed)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
