import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("동기화") {
                LabeledContent("저장 방식") {
                    Label("이 기기에 저장", systemImage: "iphone")
                        .foregroundStyle(.secondary)
                }

                Text("로컬 라이브러리를 완성한 뒤 iCloud 동기화를 연결할 예정이에요.")
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
