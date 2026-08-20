import SwiftData
import SwiftUI

struct PerformanceRecordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let song: Song

    @State private var draftID = UUID()
    @State private var performedAt = Date()
    @State private var serviceType = ""
    @State private var selectedKey: MusicalKey?
    @State private var leader = ""
    @State private var notes = ""
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
            Section("예배 정보") {
                DatePicker(
                    "날짜",
                    selection: $performedAt,
                    displayedComponents: .date
                )

                TextField("예배 종류 (필수)", text: $serviceType)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .accessibilityHint("예: 주일 2부 예배")

                Picker("연주 키", selection: $selectedKey) {
                    Text("선택 안 함")
                        .tag(nil as MusicalKey?)

                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName)
                            .tag(key as MusicalKey?)
                    }
                }

                TextField("인도자 (선택)", text: $leader)
                    .submitLabel(.done)
            }

            Section("메모 (선택)") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .accessibilityLabel("예배 기록 메모")
            }
        }
        .navigationTitle("예배 기록 추가")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
            }
        }
        .alert(
            "예배 기록을 저장하지 못했어요",
            isPresented: saveErrorIsPresented
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "입력 내용을 확인하고 다시 시도해 주세요.")
        }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func save() {
        let draft = PerformanceRecordDraft(
            id: draftID,
            performedAt: performedAt,
            serviceType: serviceType,
            leader: leader,
            musicalKey: selectedKey,
            notes: notes
        )

        do {
            _ = try PerformanceRecordPersistence.add(
                draft,
                to: song,
                in: modelContext
            )
            dismiss()
        } catch {
            // Keep every field intact so the user can correct or retry the save.
            saveErrorMessage = error.localizedDescription
        }
    }
}
