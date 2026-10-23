import SwiftUI
import Vultus

/// 지표 줄 — BPM · FPS · 선명도 · 얼굴 크기 · 줌과 화면 배율 · 표정.
struct MetricsBar: View {
    @ObservedObject var measuring: SampleMeasuring
    @ObservedObject var faceState: SampleFaceState
    /// 프리뷰 뷰가 알려 준 좌표 변환 — 화면 배율을 구하는 데 쓴다.
    let previewTransform: VultusPreviewTransform?
    /// 정사각 프리뷰의 한 변(pt).
    let previewSide: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            metric("BPM",
                   value: Self.displayBpmText(measuring.displayBpm),
                   tint: Self.displayBpmTint(measuring.displayBpm))
            metric("FPS", value: measuring.displayBpm.fps > 0 ? "\(measuring.displayBpm.fps)" : "--")
            metric("선명도",
                   value: measuring.state.isMeasuring
                       ? String(format: "%.2f", measuring.signalClarity.score) : "--",
                   tint: measuring.state.isMeasuring
                       ? Self.clarityTint(measuring.signalClarity) : .white)
            faceSizeMetric
            // 자동 맞춤이 얼굴 크기를 나눈 몫 — 카메라 줌 · 화면 배율(프리뷰를 늘린 정도). 둘을 곱한 것이 화면의 크기다.
            metric("줌·화면", value: framingText)
            metric("표정", value: measuring.emotion?.label ?? "--")
        }
        .padding(.vertical, 10)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    /// "줌 · 화면 배율". 화면 배율은 SDK 가 알려 준 변환의 배율 ÷ 같은 뷰의 기본(덮기) 배율이다.
    private var framingText: String {
        guard let zoom = measuring.framingZoom else { return "--" }
        var display = "--"
        if let t = previewTransform, previewSide > 0 {
            let base = VultusPreviewTransform(imageSize: t.imageSize,
                                              viewSize: CGSize(width: previewSide, height: previewSide),
                                              fill: .fill, mirrored: t.mirrored, rotationDegrees: t.rotationDegrees)
            display = String(format: "%.2f", Double(t.scale / base.scale))
        }
        return String(format: "%.2f", Double(zoom)) + "·" + display
    }

    /// 얼굴 bbox 긴 변(px). 색은 SDK 촬영 조건을 따른다 — 쓸 만하면 초록, 작으면 노랑, 너무 가까우면 주황.
    /// 거리를 감으로 맞추면 매번 달라지므로, 숫자로 확인할 수 있게 둔다.
    private var faceSizeMetric: some View {
        let side = faceState.face.map { max($0.boundingBox.width, $0.boundingBox.height) }
        return metric(
            "얼굴",
            value: side.map { "\(Int($0.rounded()))" } ?? "--",
            tint: side.map { _ in FaceSizeTarget.tint(faceState.captureCause) } ?? .white
        )
    }

    /// 새 표시용 BPM — 값이 없는 구간에는 숫자를 그리지 않는다(SDK 문서의 권고).
    private static func displayBpmText(_ value: VultusDisplayBpm) -> String {
        value.state == .warmingUp ? "--" : "\(value.bpm)"
    }

    /// 아직 흔들리는 구간은 노랑 — 상태를 색으로도 드러낸다.
    private static func displayBpmTint(_ value: VultusDisplayBpm) -> Color {
        switch value.state {
        case .warmingUp: return .white
        case .estimating: return .yellow
        case .stable: return .green
        }
    }

    /// 선명도 수준은 색으로만 — 흰색 아직 정해지지 않음 · 노랑 나쁨 · 파랑 보통 · 초록 좋음. 측정 초반(`.warmingUp`)에는
    /// 수준이 정해지지 않는다 — 그동안의 점수는 참고용이다.
    private static func clarityTint(_ clarity: VultusSignalClarity) -> Color {
        switch clarity.level {
        case .warmingUp: return .white
        case .poor: return .yellow
        case .fair: return .blue
        case .good: return .green
        }
    }

    private func metric(_ title: String, value: String, tint: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit()).bold()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}
