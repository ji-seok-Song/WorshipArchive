import SwiftUI

struct PersistenceUnavailableView: View {
    let error: ModelContainerStartupError

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 72, height: 72)
                .background(.red.opacity(0.1), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .font(.title3.bold())

                Text("앱을 완전히 종료한 뒤 다시 열어 주세요. 문제가 계속되면 기기의 저장 공간을 확인해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(error.details)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 460)
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}
