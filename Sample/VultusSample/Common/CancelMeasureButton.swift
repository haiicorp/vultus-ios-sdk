import SwiftUI

/// 측정 취소 버튼 — 측정이 진행 중일 때 앱 정보 버튼 자리에 놓는다. 누르면 그 측정을 버린다(전송하지 않는다 — 보내는 중이면 전송을 끊는다).
/// 무엇을 부를지는 화면이 넘긴다(그 길의 세션).
struct CancelMeasureButton: View {
    let cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            Image(systemName: "xmark")
                .font(.headline)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("측정 취소")
    }
}
