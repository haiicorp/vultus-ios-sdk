import SwiftUI

/// 준비 · 실패 화면 — 메시지 하나와, 기다리는 중이면 진행 표시.
struct PreparingView: View {
    let message: String
    let showProgress: Bool

    var body: some View {
        VStack(spacing: 16) {
            if showProgress {
                ProgressView().scaleEffect(1.4)
            }
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
