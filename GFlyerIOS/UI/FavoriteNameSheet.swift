import SwiftUI

/// 地圖工具列 ☆ 的命名 sheet(GFlyer-Suite docs/features/favorite-add.md §3.3、§3.4、第 5 節「iOS 0.6.11 實作重點」)。
/// 用一行 `.modifier` 掛在 `MainView` 一直存在的那一層,sheet 本體不寫進 `MainView.body`(那裡要保持拆層,
/// docs/RELEASE_PROCESS.md 不可回退的決定 #4)。不掛在 `MapToolBar`:工具列在搜尋結果出現時會離開畫面,
/// 打到一半的名稱會無聲消失。
///
/// - `.sheet(item:)` 把按 ☆ 時記下的請求傳進內容,按「收藏」存的就是 sheet 上顯示的那個座標(待決事項 2)。
/// - 往下滑關掉等於「取消」:什麼都不存、沒有訊息。已經排出去的反查不撤回。
struct FavoriteNameSheet: ViewModifier {
    @Binding var request: FavoriteNameRequest?
    /// 插隊反查那一點所在的格子(`SimulationController.favoriteNameLabel(for:)`):查到是標籤,查不到是 nil。
    let lookUp: @MainActor (GeoCoordinate) async -> String?
    /// 按「收藏」:名稱欄位的文字與 sheet 上的座標。
    let onConfirm: (String, GeoCoordinate) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $request) { presented in
            FavoriteNameForm(request: presented, lookUp: lookUp, onConfirm: onConfirm)
        }
    }
}

/// 命名 sheet 的內容。外觀照座標圖鑑的回報 sheet:「取消」「收藏」在上方工具列,半高。
/// 名稱欄位與「正在查詢地名…」是這一次打開自己的狀態(`FavoriteNameField`):每按一次 ☆ 是新的 id,
/// `.sheet(item:)` 建一個新的畫面,所以每次都重新預填,上一次取消掉的字不留。
private struct FavoriteNameForm: View {
    let request: FavoriteNameRequest
    let lookUp: @MainActor (GeoCoordinate) async -> String?
    let onConfirm: (String, GeoCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var field: FavoriteNameField

    init(
        request: FavoriteNameRequest,
        lookUp: @escaping @MainActor (GeoCoordinate) async -> String?,
        onConfirm: @escaping (String, GeoCoordinate) -> Void
    ) {
        self.request = request
        self.lookUp = lookUp
        self.onConfirm = onConfirm
        _field = State(initialValue: FavoriteNameField(suggestedName: request.suggestedName))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(request.coordinate.display)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    nameField
                }
            }
            .navigationTitle(FavoriteAddTexts.dialogTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FavoriteAddTexts.cancelButton) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 永遠可以按:欄位空白就用「收藏 <座標>」,等地名的時候也可以按(和改名不同,不依欄位停用)
                    Button(FavoriteAddTexts.confirmButton) {
                        onConfirm(field.text, request.coordinate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .task { await waitForPlaceName() }
    }

    /// 「名稱」小字、單行的欄位,與等反查時欄位下方的提示。打開時不自動取得焦點,也不加 `.onSubmit`:
    /// 鍵盤上的動作鍵只收起鍵盤,不會送出(和 Android 相同)。
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FavoriteAddTexts.nameLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(FavoriteAddTexts.namePlaceholder, text: nameBinding)
            if field.isLookingUp {
                Text(FavoriteAddTexts.lookingUpHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 只有文字真的改變才算使用者動過欄位(`FavoriteNameField.edit` 自己會比較;只是點進欄位不算)。
    private var nameBinding: Binding<String> {
        Binding(
            get: { field.text },
            set: { field.edit($0) }
        )
    }

    /// 打開時沒有預填才等:同時等插隊反查與 10 秒,先到的決定結果。sheet 關掉時這個 task 被取消,
    /// 反查照樣進行、標籤照樣進快取與清單(規格 §3.4、§3.6)。
    private func waitForPlaceName() async {
        guard field.isLookingUp else { return }
        let coordinate = request.coordinate
        let lookUp = self.lookUp
        let outcome = await FavoriteNameLookup.firstOutcome(lookUp: { await lookUp(coordinate) })
        field.finishLookup(outcome)
    }
}
