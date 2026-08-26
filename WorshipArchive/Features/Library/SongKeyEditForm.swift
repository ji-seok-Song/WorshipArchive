import SwiftData
import SwiftUI

struct SongKeyEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let sheet: SongSheet

    @State private var musicalKey: MusicalKey?
    @State private var errorMessage: String?

    init(sheet: SongSheet) {
        self.sheet = sheet
        _musicalKey = State(initialValue: sheet.musicalKey)
    }

    var body: some View {
        Form {
            Section {
                Picker("키", selection: $musicalKey) {
                    Text("미지정").tag(nil as MusicalKey?)

                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName).tag(key as MusicalKey?)
                    }
                }
            } header: {
                Text(sheet.song?.title ?? "악보")
            } footer: {
                Text("선택한 키는 현재 곡의 이 악보에 적용됩니다.")
            }
        }
        .navigationTitle("키 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
                    .disabled(musicalKey == sheet.musicalKey)
            }
        }
        .alert(
            "키를 저장하지 못했어요",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func save() {
        do {
            try ArchiveLibraryEditing.updateSheetKey(
                sheet,
                musicalKey: musicalKey,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
