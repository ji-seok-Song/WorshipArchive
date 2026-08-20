import SwiftUI

struct SettingsView: View {
    let syncCoordinator: ArchiveSyncCoordinator?

    init(syncCoordinator: ArchiveSyncCoordinator? = nil) {
        self.syncCoordinator = syncCoordinator
    }

    var body: some View {
        Form {
            Section("동기화") {
                if let syncCoordinator {
                    syncStatus(syncCoordinator.status)

                    if canRetry(syncCoordinator.status) {
                        Button {
                            syncCoordinator.retry()
                        } label: {
                            Label("지금 다시 시도", systemImage: "arrow.clockwise")
                        }
                        .disabled(isSyncing(syncCoordinator.status))
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
                LabeledContent("버전", value: appVersion)
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
                Label(localOnlyText(reason), systemImage: "icloud.slash")
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

    private func localOnlyText(_ reason: CloudAccountAvailability) -> String {
        switch reason {
        case .noAccount:
            "iCloud 로그인 필요"
        case .restricted:
            "계정에서 사용 제한됨"
        case .temporarilyUnavailable, .couldNotDetermine:
            "일시적으로 사용할 수 없음"
        case .available:
            "사용 중"
        }
    }

    private func canRetry(_ status: ArchiveSyncCoordinator.Status) -> Bool {
        switch status {
        case .localOnly, .offline, .failed:
            true
        case .checking, .syncing, .active:
            false
        }
    }

    private func isSyncing(_ status: ArchiveSyncCoordinator.Status) -> Bool {
        if case .syncing = status { return true }
        return false
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
