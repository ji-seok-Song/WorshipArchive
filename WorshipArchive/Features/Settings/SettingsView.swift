import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(syncCoordinator: ArchiveSyncCoordinator? = nil) {
        _viewModel = State(
            initialValue: SettingsViewModel(syncCoordinator: syncCoordinator)
        )
    }

    var body: some View {
        Form {
            Section("동기화") {
                if let status = viewModel.syncStatus {
                    syncStatus(status)

                    if viewModel.canRetry(status) {
                        Button {
                            viewModel.retrySync()
                        } label: {
                            Label("지금 다시 시도", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isSyncing(status))
                    }
                } else {
                    LabeledContent("저장 방식") {
                        Label("이 기기에 저장", systemImage: "iphone")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("악보는 먼저 이 기기에 안전하게 저장됩니다. iCloud 연결이 끊겨도 이 기기에 저장된 내용은 유지됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("악보 분석") {
                LabeledContent("인식 언어", value: "한국어 · 영어")
                LabeledContent("자동 저장", value: "사용 안 함")
            }

            Section("앱 정보") {
                LabeledContent("앱 이름", value: "찬양서랍")
                LabeledContent("버전", value: viewModel.appVersion)
            }
        }
        .navigationTitle("설정")
    }

    @ViewBuilder
    private func syncStatus(_ status: ArchiveSyncCoordinator.Status) -> some View {
        switch status {
        case .checking:
            LabeledContent("iCloud") { Label("확인 중", systemImage: "icloud") }
        case let .syncing(pendingCount):
            LabeledContent("iCloud") {
                Label("동기화 중 · \(pendingCount)개", systemImage: "icloud.and.arrow.up")
            }
        case let .active(_, lastSuccess):
            LabeledContent("iCloud") {
                Label("사용 중", systemImage: "checkmark.icloud")
                    .foregroundStyle(.green)
            }
            if let lastSuccess {
                LabeledContent("최근 PDF 동기화") {
                    Text(lastSuccess, format: .dateTime.month().day().hour().minute())
                }
            }
        case let .localOnly(reason, pendingCount):
            LabeledContent("iCloud") {
                Label(viewModel.localOnlyText(reason), systemImage: "icloud.slash")
                    .foregroundStyle(.orange)
            }
            if pendingCount > 0 {
                LabeledContent("업로드 대기", value: "\(pendingCount)개")
            }
        case let .offline(pendingCount):
            LabeledContent("iCloud") {
                Label("오프라인", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            LabeledContent("업로드 대기", value: "\(pendingCount)개")
        case let .failed(message, pendingCount):
            Label(message, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
            if pendingCount > 0 {
                LabeledContent("업로드 대기", value: "\(pendingCount)개")
            }
        }
    }

}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
