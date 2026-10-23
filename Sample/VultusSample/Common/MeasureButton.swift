import SwiftUI
import Vultus

/// 측정 시작 · 종료 버튼. 무엇을 부를지는 화면이 넘긴다(그 길의 세션).
struct MeasureButton: View {
    let state: VultusMeasureState
    /// 진행은 **SDK 가 센다.** 앱이 벽시계로 세면 얼굴을 놓친 구간까지 진행으로 쳐서,
    /// 서버가 계산하지 못하는 측정을 "다 모았다" 고 표시하게 된다.
    let progress: VultusMeasureProgress
    /// 측정을 시작하고 끝날 때까지 기다린다 — 결말(또는 거절 사유)을 돌려준다.
    let start: () async -> VultusMeasureOutcome
    let stop: () -> Void
    /// 결말을 받는다.
    let onOutcome: (VultusMeasureOutcome) -> Void
    /// 결과 요약을 바꾼다 — 시작할 때 지운다.
    let onResultSummary: (String?) -> Void

    var body: some View {
        Button {
            switch state {
            case .idle:
                onResultSummary(nil)
                // 측정이 끝나면 결말이 돌아온다 — 시작을 거절했으면 그 사유다.
                Task { onOutcome(await start()) }
            case .started:
                stop()
            default:
                break
            }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        // 측정 중에는 빨간색으로 바꾼다. 시작 직후에는 맥파 버퍼가 차기를 기다리느라
        // BPM·그래프가 비어 있으므로, 색 변화가 측정이 시작됐다는 신호가 된다.
        .tint(state == .started ? .red : .accentColor)
        .disabled(state != .idle && state != .started)
    }

    private var title: String {
        switch state {
        case .idle:     return "측정 시작"
        // 라이선스 확인 · 준비 · 비대화형 시작의 맞춤과 카운트다운을 기다린다 — 다시 누르지 않게 막아 둔다.
        case .starting: return "준비 중..."
        case .adjustingCamera: return "카메라 조정 중..."
        // 남은 시간이 아니라 **충족률**이다. 진행이 0 으로 돌아가는 것(앵커 전 끊김)도
        // 그대로 보여야 사용자가 자세를 고칠 이유를 안다.
        case .started:
            return "측정중 \(progress.percent)% (\(progress.elapsedSeconds)초), 탭하여 종료"
        case .stopped:  return "정리 중..."
        case .finished: return "결과 전송 중..."
        case .submitting: return "결과 전송 중..."
        case .canceled: return "취소됨"
        }
    }
}
