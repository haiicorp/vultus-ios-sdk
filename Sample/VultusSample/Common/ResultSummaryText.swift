import SwiftUI

/// 측정 결과 요약 한 줄 — 시작 거절 · 전송 완료 · 취소 · 실패가 모두 여기로 모인다. 없으면 그리지 않는다.
struct ResultSummaryText: View {
    let summary: String?

    var body: some View {
        if let summary {
            Text(summary).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
