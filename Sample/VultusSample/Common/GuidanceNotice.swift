import SwiftUI
import Vultus

/// 측정 안내. SDK 가 정해 주는 안내 하나(`VultusGuidance`)를 띄운다 — 측정 전에는 촬영 조건을, 측정 중에는
/// 촬영 조건 · 흔들림 · 신호 가운데 가장 앞선 것을 알린다.
///
/// **안내 전용이다** — 측정은 그대로 이어진다. 고칠 것이 없으면 아무것도 띄우지 않는다.
struct GuidanceNotice: View {
    let guidance: VultusGuidance

    var body: some View {
        if let message = Self.message(guidance) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(8)
                .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 안내를 사용자에게 보일 문장으로 옮긴다. 고칠 것이 없으면 nil.
    private static func message(_ guidance: VultusGuidance) -> String? {
        switch guidance {
        case .none:
            return nil
        case .condition(let condition):
            switch condition.cause {
            case .none: return nil
            case .noFace: return "얼굴이 보이지 않습니다. 화면 안에 얼굴을 맞춰 주세요."
            case .offFrame: return "얼굴이 화면 밖으로 나갔습니다. 가운데로 와 주세요."
            case .tooFar: return "조금 더 가까이 와 주세요."
            case .tooClose: return "조금 더 멀리 떨어져 주세요."
            case .headTilted: return "기기를 눈높이에 두고 정면을 봐 주세요."
            case .headTurned: return "화면을 정면으로 봐 주세요."
            case .tooDark: return "주변이 어둡습니다. 밝은 곳에서 측정해 주세요."
            case .framing: return "카메라를 맞추고 있습니다. 그대로 계셔 주세요."
            }
        case .motion(let stability):
            return stability.cause == .faceMotion
                ? "잠시 움직이지 말아 주세요."
                : "기기가 흔들리고 있습니다. 기기를 고정하거나 두 손으로 잡아 주세요."
        case .poorSignal:
            return "신호가 약합니다. 조명과 자세를 확인해 주세요."
        }
    }
}
