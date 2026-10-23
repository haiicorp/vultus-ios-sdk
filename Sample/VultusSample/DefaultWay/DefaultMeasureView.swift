import AVFoundation
import SwiftUI
import Vultus

/// **Default 길 측정 화면** — SDK 가 카메라 · 프리뷰 · 자동 맞춤(줌)을 쥔다. 두 길이 갈리는 곳은 이 화면과
/// `CustomMeasureView` 뿐이고, 화면을 이루는 조각(`Common`)은 값만 받아 그린다.
///
/// 1. 카메라 권한을 얻은 뒤 프리뷰 뷰를 놓고 `Vultus.openDefaultSession(preview:)` 으로 세션을 연다 — 아래 `DefaultWayPreview`
/// 2. 상태를 세션의 **스냅숏** 하나로 읽는다 — 상태 · 진행 · 안내 · BPM 이 같은 순간의 값이다. 그래프 · 얼굴 · 표정은 따로 온다
/// 3. `session.startMeasure` 로 측정하고 결말을 돌려받는다 · `session.stopMeasure` 로 멈춘다 · `session.cancelMeasure` 로 버린다
/// 4. 떠날 때 진행 중인 측정을 버린다(`session.cancelMeasure()`) — 세션은 프리뷰 뷰가 창에서 떨어지면 스스로 닫힌다. 닫기만으로는
///    멈춘 측정(정리 · 전송 중)이 끝까지 보내진다
struct DefaultMeasureView: View {
    /// 화면이 열리자마자 버튼 없이 시작한다(비대화형).
    let autoStart: Bool

    init(autoStart: Bool = false) { self.autoStart = autoStart }

    // 2. 상태 — 세션을 열면 잇는다. 얼굴은 30Hz 라 따로 든다(`SampleFaceState`).
    @StateObject private var measuring = SampleMeasuring()
    // ⚠️ 얼굴은 `@StateObject` 가 아니라 `@State` 로 든다 — `@StateObject` 는 소유와 함께 구독도 해서 30Hz 로 바뀌는 얼굴을 이 화면
    // 전체가 받아 다시 그려진다. 관찰은 잎 뷰(`@ObservedObject`)만 한다. 그래프 신호도 같은 까닭으로 `measuring.signal` 을 그래프만 본다.
    @State private var faceState = SampleFaceState()
    /// 1. 프리뷰 뷰를 놓으며 연 세션.
    @State private var session: VultusDefaultSession?

    /// 카메라 권한. **요청은 앱이 한다** — SDK 는 확인만 하고 거절 사유를 돌려준다.
    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    /// 카메라를 열지 못한 사유. 화면에 그대로 보여 준다.
    @State private var startError: String?
    /// 프리뷰 뷰가 알려 준 좌표 변환 — 자동 맞춤의 배율 · 이동이 들어 있다.
    @State private var previewTransform: VultusPreviewTransform?
    /// 정사각 프리뷰의 한 변(pt) — 화면 배율을 구하는 데 쓴다.
    @State private var previewSide: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MeasurePreviewBox(faceState: faceState, transform: previewTransform, countdown: measuring.countdown,
                              onSideChange: { previewSide = $0 }) {
                // 1. 프리뷰 — 권한이 확정된 뒤에 연다. 먼저 열면 SDK 가 `cameraPermissionDenied` 를 돌려준다.
                if cameraAuthorized {
                    DefaultWayPreview(camera: .front, onTransform: { previewTransform = $0 }) { opened in
                        session = opened
                        measuring.bind(opened)
                        faceState.bind(opened)
                    } onError: { error in
                        startError = "카메라를 열지 못했습니다 — code \(error.rawValue)"
                    }
                }
            }

            // 프리뷰 위에 얹는 조작 · 지표 계층. 프리뷰와 달리 안전 영역 안쪽에 둔다.
            VStack(spacing: 12) {
                MetricsBar(measuring: measuring, faceState: faceState,
                           previewTransform: previewTransform, previewSide: previewSide)
                // 그래프는 지표창 바로 아래에 붙인다. 화면 하단에 두면 측정 자세를 잡는 동안 얼굴 영역을 가린다.
                MeasureSignalBox(signal: measuring.signal)

                if let startError {
                    Text(startError)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.8), in: Capsule())
                }

                // 측정 안내. 측정 전에는 촬영 조건을, 측정 중에는 가장 앞선 안내 하나를 띄운다.
                GuidanceNotice(guidance: measuring.guidance)

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    ResultSummaryText(summary: measuring.resultSummary)
                    HStack(spacing: 8) {
                        MeasureButton(
                            state: measuring.state,
                            progress: measuring.progress,
                            // 3. 측정 — 끝날 때까지 기다렸다가 결말을 돌려받는다. appendix 는 측정 meta 에 그대로 실린다(앱이 싣는 값이다).
                            start: {
                                guard let session else { return .refused(.notInitialized) }
                                return await session.startMeasure(analysisWindow: measureSeconds,
                                                                  appendix: ["installationId": InstallationId.current])
                            },
                            stop: { session?.stopMeasure() },
                            onOutcome: { measuring.show($0) },
                            onResultSummary: { measuring.resultSummary = $0 })
                        // 측정이 진행 중이면 앱 정보 자리에 취소를 둔다 — `cancelMeasure` 는 그 측정을 버리고 전송하지 않는다(보내는 중이면 전송을 끊는다).
                        if measuring.state != .idle && measuring.state != .canceled {
                            CancelMeasureButton(cancel: { session?.cancelMeasure() })
                        } else {
                            AppInfoButton()
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            requestCameraAccessIfNeeded()
        }
        // 4. 떠나면 진행 중인 측정을 버린다.
        .onDisappear { session?.cancelMeasure() }
        // 비대화형 시작 — 카메라가 프레임을 내기 시작하면(회전이 정해지면) 버튼 없이 시작한다. 맞춰지면 카운트다운
        // (프리뷰 가운데)을 센 뒤 시작하고, 제한 시간 안에 맞춰지지 않으면 시작하지 않는다. 화면을 떠나면 이 작업과 함께 측정도 취소된다.
        .task(id: session.map { ObjectIdentifier($0) }) {
            guard autoStart, let session else { return }
            var decided = false
            for await orientation in session.effectiveOrientation.values where orientation != nil { decided = true; break }
            // 작업이 취소되면 흐름이 값 없이 끝난다 — 그때는 시작하지 않는다(SwiftUI 가 작업을 다시 띄우며 앞 작업을 취소하는 경우도 있다).
            guard decided, !Task.isCancelled else { return }
            measuring.show(await session.startMeasure(analysisWindow: measureSeconds,
                                                      mode: .nonInteractive(),
                                                      appendix: ["installationId": InstallationId.current]))
        }
    }

    /// 권한을 묻고 결과를 상태에 담는다. 이미 허용됐으면 아무 일도 하지 않는다.
    private func requestCameraAccessIfNeeded() {
        guard !cameraAuthorized else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                cameraAuthorized = granted
                if !granted { startError = "카메라 권한이 필요합니다. 설정에서 허용해 주세요." }
            }
        }
    }
}

/// SDK 의 `VultusPreviewView` 를 SwiftUI 에 얹는 **예제 래퍼**.
///
/// SDK 패키지에는 SwiftUI 의존성을 두지 않는다 — 이 래퍼가 그 경계를 메운다. 좌표 변환 · 미러 ·
/// 얼굴 가이드 표시는 SDK 뷰 안에서 끝나므로 앱이 그릴 것은 얼굴 박스뿐이다.
private struct DefaultWayPreview: UIViewRepresentable {
    /// 어느 카메라를 열지. 선택 · 바인딩 · 미러는 SDK 가 한다.
    let camera: VultusCameraSelection
    /// 프리뷰 뷰가 쓰는 좌표 변환이 바뀌면 받는다 — 자동 맞춤이 프리뷰를 늘리고 옮기므로 오버레이는 이 변환을 써야 한다.
    var onTransform: (VultusPreviewTransform) -> Void = { _ in }
    /// 세션을 열었다.
    let onOpen: (VultusDefaultSession) -> Void
    let onError: (VultusError) -> Void

    func makeUIView(context: Context) -> VultusPreviewView {
        let view = VultusPreviewView()
        view.fill = .fill
        view.onTransformChange = { transform in DispatchQueue.main.async { onTransform(transform) } }
        // 맞추는 동안 얼굴이 렌즈 중심(광축)에서 벗어나면 목적지점(렌즈 중심) · 현재 지점(얼굴) crosshair 를 띄운다. 모양은
        // 앱의 뷰로 바꿀 수 있다: SDK 는 뷰의 중심을 그 점에 맞추고 보이거나 숨기기만 한다. 여기서는 목적지점만 바꾸고 현재
        // 지점은 기본 모양(×)을 쓴다.
        view.showsFramingCrosshair = true
        let crosshair = UIHostingController(rootView: SampleCrosshair()).view!
        crosshair.backgroundColor = .clear
        crosshair.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        view.framingTargetCrosshairView = crosshair
        // 뷰를 만들고 곧바로 — 다음 메인 루프에서 — 연다. `makeUIView` 는 SwiftUI 가 화면을 갱신하는 도중에 불리는데, 연 세션을
        // 화면 상태에 담으면 갱신 중에 상태가 바뀌어 SwiftUI 가 경고한다(「Publishing changes from within view updates」).
        // ⚠️ 닫기를 부르지 않는다 — 창에서 떨어지면 세션이 스스로 닫히므로 `dismantleUIView` 에서 닫을 것이 없다.
        DispatchQueue.main.async {
            switch Vultus.openDefaultSession(preview: view, selection: camera) {
            case let .success(session):
                // 얼굴을 보일 자리 — 프리뷰 폭의 65 %, 가운데. SDK 가 줌과 프리뷰 배율로 얼굴을 여기에 얹는다.
                session.setFaceGuide(VultusFaceGuide(widthFraction: 0.65, center: CGPoint(x: 0.5, y: 0.5)))
                onOpen(session)
            case let .failure(error):
                onError(error)
            }
        }
        return view
    }

    func updateUIView(_ uiView: VultusPreviewView, context: Context) {}
}

/// 맞춤 crosshair 의 앱 모양 예제 — 고리와 가운데 점.
private struct SampleCrosshair: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.85), lineWidth: 2).padding(2)
            Circle().fill(Color.white.opacity(0.85)).frame(width: 5, height: 5)
        }
    }
}
