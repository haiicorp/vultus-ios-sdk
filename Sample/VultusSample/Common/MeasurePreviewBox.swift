import SwiftUI
import Vultus

/// 프리뷰를 화면에 얼마나 크게 그릴지.
enum PreviewLayout {
    /// 정사각 프리뷰의 한 변 — 화면의 가로 · 세로 중 짧은 쪽에 대한 비율.
    static let sideFraction: CGFloat = 0.9
}

/// 프리뷰 자리. 프리뷰는 **정사각형** — 화면의 가로 · 세로 중 짧은 쪽의 90 % 를 한 변으로 화면 정중앙에 둔다.
/// 오버레이는 프리뷰와 같은 좌표계여야 하므로 같은 상자에 그린다.
///
/// 얼굴은 30Hz 로 바뀌므로 이 조각만 `faceState` 를 본다. 비대화형 시작의 카운트다운은 프리뷰 가운데에 크게 그린다.
struct MeasurePreviewBox<Preview: View>: View {
    @ObservedObject var faceState: SampleFaceState
    /// 프리뷰 뷰가 알려 준 좌표 변환 — 자동 맞춤의 배율 · 이동이 들어 있다.
    let transform: VultusPreviewTransform?
    /// 비대화형 시작의 카운트다운(남은 초). 없으면 그리지 않는다.
    var countdown: Int? = nil
    /// 정사각 프리뷰의 한 변(pt)이 정해지거나 바뀌면 받는다.
    var onSideChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        GeometryReader { screen in
            let side = min(screen.size.width, screen.size.height) * PreviewLayout.sideFraction
            ZStack {
                preview()
                if let face = faceState.face {
                    FaceOverlay(face: face,
                                transform: transform,
                                viewSize: CGSize(width: side, height: side),
                                rotationDegrees: faceState.overlayRotationDegrees,
                                captureCause: faceState.captureCause)
                }
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: side * 0.3, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .onAppear { onSideChange(side) }
            .onChange(of: side) { onSideChange($0) }
            .clipped()
            .position(x: screen.size.width / 2, y: screen.size.height / 2)
        }
    }
}
