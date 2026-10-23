// AVCaptureSession 등 AVFoundation 타입은 Sendable 로 표시돼 있지 않지만,
// 여기서는 전용 직렬 큐에서만 만지므로 안전하다.
@preconcurrency import AVFoundation
import Combine
import SwiftUI
import Vultus

/// **Custom 길 측정 화면** — 앱이 카메라를 쥐고 SDK 세션에 프레임을 넘긴다. 두 길이 갈리는 곳은 이 화면과
/// `DefaultMeasureView` 뿐이고, 화면을 이루는 조각(`Common`)은 값만 받아 그린다.
///
/// 세션은 이 화면의 것이다 — 들어올 때 열고 떠날 때 닫는다.
/// 1. 카메라 권한을 묻고 `Vultus.openCustomSession()` 으로 세션을 연 뒤 카메라를 구성한다 — 아래 `CustomWayCamera`.
///    열린 세션은 하나라 Default 세션이 열려 있는 동안에는 열리지 않는다
/// 2. 상태를 세션의 **스냅숏** 하나로 읽는다 — Default 길과 같은 값이다
/// 3. 프리뷰를 SDK 프리뷰 뷰에 그리고 세션에 붙인다 — 아래 `CustomWayPreview`
/// 4. `session.startMeasure` 로 측정하고 결말을 돌려받는다 · `session.stopMeasure` 로 멈춘다 · `session.cancelMeasure` 로 버린다
/// 5. 떠날 때 진행 중인 측정을 버리고(`session.cancelMeasure()`) `session.close()` 하고 카메라를 멈춘다
struct CustomMeasureView: View {
    /// 화면이 열리자마자 버튼 없이 시작한다(비대화형).
    let autoStart: Bool

    init(autoStart: Bool = false) { self.autoStart = autoStart }

    @StateObject private var camera = CustomWayCamera()

    var body: some View {
        Group {
            if let session = camera.session {
                SessionMeasureView(session: session, captureSession: camera.captureSession, autoStart: autoStart,
                                   onPreviewView: camera.keepPreview)
            } else if let message = camera.errorMessage {
                PreparingView(message: message, showProgress: false)
            } else {
                PreparingView(message: "카메라를 여는 중입니다...", showProgress: true)
            }
        }
        // 1 · 5. 세션과 카메라
        .onAppear { camera.open() }
        .onDisappear { camera.close() }
    }
}

/// 열린 세션으로 측정 화면을 그린다 — 세션이 생긴 뒤에야 흐름을 구독할 수 있어 따로 뺐다.
private struct SessionMeasureView: View {
    let session: VultusCustomSession
    let captureSession: AVCaptureSession
    let autoStart: Bool
    /// 프리뷰 뷰가 생기면 받는다 — 카메라를 멈춘 뒤 떼려고 카메라가 쥔다.
    let onPreviewView: (VultusPreviewView) -> Void

    // 2. 상태 — 얼굴은 30Hz 라 따로 든다(`SampleFaceState`).
    @StateObject private var measuring = SampleMeasuring()
    // ⚠️ 얼굴은 `@StateObject` 가 아니라 `@State` 로 든다 — `@StateObject` 는 소유와 함께 구독도 해서 30Hz 로 바뀌는 얼굴을 이 화면
    // 전체가 받아 다시 그려진다. 관찰은 잎 뷰(`@ObservedObject`)만 한다. 그래프 신호도 같은 까닭으로 `measuring.signal` 을 그래프만 본다.
    @State private var faceState = SampleFaceState()

    /// 프리뷰 뷰가 알려 준 좌표 변환 — 표시 맞춤의 배율 · 이동이 들어 있다.
    @State private var previewTransform: VultusPreviewTransform?
    /// 정사각 프리뷰의 한 변(pt) — 화면 배율을 구하는 데 쓴다.
    @State private var previewSide: CGFloat = 0


    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MeasurePreviewBox(faceState: faceState, transform: previewTransform, countdown: measuring.countdown,
                              onSideChange: { previewSide = $0 }) {
                // 3. 프리뷰 — 앱의 촬영 세션을 SDK 프리뷰 뷰에 그리고 세션에 붙인다
                CustomWayPreview(captureSession: captureSession, session: session, onView: onPreviewView,
                               onTransform: { previewTransform = $0 })
            }

            // 프리뷰 위에 얹는 조작 · 지표 계층. 프리뷰와 달리 안전 영역 안쪽에 둔다.
            VStack(spacing: 12) {
                MetricsBar(measuring: measuring, faceState: faceState,
                           previewTransform: previewTransform, previewSide: previewSide)
                // 그래프는 지표창 바로 아래에 붙인다. 화면 하단에 두면 측정 자세를 잡는 동안 얼굴 영역을 가린다.
                MeasureSignalBox(signal: measuring.signal)

                // 측정 안내. 측정 전에는 촬영 조건을, 측정 중에는 가장 앞선 안내 하나를 띄운다.
                GuidanceNotice(guidance: measuring.guidance)

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    ResultSummaryText(summary: measuring.resultSummary)
                    HStack(spacing: 8) {
                        MeasureButton(
                            state: measuring.state,
                            progress: measuring.progress,
                            // 4. 측정 — 끝날 때까지 기다렸다가 결말을 돌려받는다. appendix 는 측정 meta 에 그대로 실린다(앱이 싣는 값이다).
                            start: {
                                await session.startMeasure(analysisWindow: measureSeconds,
                                                           appendix: ["installationId": InstallationId.current])
                            },
                            stop: { session.stopMeasure() },
                            onOutcome: { measuring.show($0) },
                            onResultSummary: { measuring.resultSummary = $0 })
                        // 측정이 진행 중이면 앱 정보 자리에 취소를 둔다 — `cancelMeasure` 는 그 측정을 버리고 전송하지 않는다(보내는 중이면 전송을 끊는다).
                        if measuring.state != .idle && measuring.state != .canceled {
                            CancelMeasureButton(cancel: { session.cancelMeasure() })
                        } else {
                            AppInfoButton()
                        }
                    }
                }
            }
            .padding()
        }
        // 2. 세션을 잇는다 — 스냅숏 · 그래프 · 표정 · 얼굴.
        .onAppear {
            measuring.bind(session)
            faceState.bind(session)
        }
        // 비대화형 시작 — 카메라가 프레임을 내기 시작하면(회전이 정해지면) 버튼 없이 시작한다. 맞춰지면 카운트다운
        // (프리뷰 가운데)을 센 뒤 시작하고, 제한 시간 안에 맞춰지지 않으면 시작하지 않는다. 화면을 떠나면 이 작업과 함께 측정도 취소된다.
        .task {
            guard autoStart else { return }
            var decided = false
            for await orientation in session.effectiveOrientation.values where orientation != nil { decided = true; break }
            // 작업이 취소되면 흐름이 값 없이 끝난다 — 그때는 시작하지 않는다(SwiftUI 가 작업을 다시 띄우며 앞 작업을 취소하는 경우도 있다).
            guard decided, !Task.isCancelled else { return }
            measuring.show(await session.startMeasure(analysisWindow: measureSeconds,
                                                      mode: .nonInteractive(),
                                                      appendix: ["installationId": InstallationId.current]))
        }
    }
}

/// **Custom 길 예제** — 앱이 카메라를 쥐고 프레임만 SDK 로 흘려보낸다.
///
/// 앱이 하는 일:
/// 1. `Vultus.openCustomSession()` 으로 세션을 열고, 비디오 출력의 delegate 로 `session.captureDelegate` 를 꽂는다.
/// 2. 프리뷰를 SDK 프리뷰 뷰에 그리고 `session.attachPreview` 로 붙인다 — 가이드 · 표시 맞춤 · 오버레이 변환([CustomWayPreview]).
/// 3. 자동 맞춤 **권고**(`session.framingAdvice`)를 따를지 정한다. SDK 는 앱의 카메라를 바꾸지 않는다 —
///    이 예제는 `session.applyFramingZoom` 으로 권고 줌을 건다.
@MainActor
private final class CustomWayCamera: ObservableObject {

    /// 열린 세션. 카메라 권한이 확정된 뒤에 열린다.
    @Published private(set) var session: VultusCustomSession?
    @Published private(set) var errorMessage: String?

    let captureSession = AVCaptureSession()

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "io.haii.vultus.sample.camera")
    private var device: AVCaptureDevice?
    private var adviceSink: AnyCancellable?
    /// 앱의 세션을 그리는 프리뷰 뷰 — 카메라를 멈춘 **뒤에** 떼려고 든다.
    private weak var preview: VultusPreviewView?
    /// 화면이 카메라를 원하는가 — 권한 응답이 오기 전에 화면을 떠났으면 열지 않는다.
    private var wanted = false

    /// 권한을 묻고 카메라 · 세션을 연다. **권한 요청은 앱이 한다** — SDK 는 측정 시작에서 확인만 한다.
    func open() {
        guard session == nil else { return }
        wanted = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self, self.wanted, self.session == nil else { return }
                guard granted else {
                    self.errorMessage = "카메라 권한이 필요합니다. 설정에서 허용해 주세요."
                    return
                }
                self.configureAndRun()
            }
        }
    }

    /// 진행 중인 측정을 버리고 카메라를 멈추고 세션을 닫는다 — 뒤이어 Default 세션이 열릴 수 있게. 닫기만으로는 멈춘 측정(정리 · 전송 중)이
    /// 끝까지 보내진다.
    func close() {
        wanted = false
        adviceSink = nil
        // 권고로 건 줌을 되돌린다 — 기기 객체는 앱 안에서 공유되어, 다음에 같은 카메라를 여는 쪽이 줌이 걸린 채 시작한다.
        if let device, device.videoZoomFactor != 1, (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = 1
            device.unlockForConfiguration()
        }
        // 프리뷰는 멈춘 **뒤에** 뗀다 — 층에서 세션을 떼는 일도 세션 구성이라, 큐의 `stopRunning` 과 겹치면 AVFoundation 이 예외로
        // 앱을 끝낸다.
        let preview = self.preview
        queue.async { [captureSession] in
            captureSession.stopRunning()
            DispatchQueue.main.async { preview?.attach(captureSession: nil) }
        }
        session?.cancelMeasure()
        session?.close()
        session = nil
    }

    /// 프리뷰 뷰를 쥔다 — `close()` 가 카메라를 멈춘 뒤 뗀다.
    func keepPreview(_ view: VultusPreviewView) {
        preview = view
    }

    private func configureAndRun() {
        let opened: VultusCustomSession
        switch Vultus.openCustomSession() {
        case .success(let value):
            opened = value
        case .failure(let error):
            errorMessage = "Vultus 세션을 열지 못했습니다 — code \(error.rawValue)"
            return
        }

        captureSession.beginConfiguration()
        // 같은 화면으로 다시 들어왔으면 지난 입력 · 출력을 떼고 새로 구성한다.
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        captureSession.sessionPreset = .vga640x480   // 분석은 480p — Default 길과 같다.

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            opened.close()
            errorMessage = "전면 카메라를 열 수 없습니다."
            return
        }
        captureSession.addInput(input)
        self.device = device

        // 코어가 기대하는 형식: 2-plane full-range YUV.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        // SDK 가 내주는 delegate 를 그대로 꽂는다 — 앱이 프레임 어댑터를 짜지 않는다. 3A 락 · 카메라 메타에 쓸
        // 디바이스도 SDK 가 프레임의 연결에서 얻는다(앱이 등록할 것이 없다).
        output.setSampleBufferDelegate(opened.captureDelegate, queue: queue)
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            opened.close()
            errorMessage = "비디오 출력을 추가할 수 없습니다."
            return
        }
        captureSession.addOutput(output)

        // 권고 캡처 설정 — 장면에 따라 바뀌는 톤 처리(HDR · 전역 톤매핑)를 끈다. 출력을 붙인 뒤라 영상 안정화도 이 출력에 걸린다.
        Vultus.applyRecommendedCapture(device, output: output)

        captureSession.commitConfiguration()

        // 30 fps 고정 — HRV 측정은 여기서 타협하지 않는다. 어두우면 fps 를 내주지 않고 밝은 곳을 안내한다.
        // 프리셋 · 입력을 확정한 **뒤**에 건다 — 구성이 바뀌면 프레임 간격이 기본값으로 돌아간다.
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }),
           (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }

        // 권고를 따른다 — 줌을 걸지 말지는 앱이 정한다. 권고는 줌을 바꿔도 되는 때(측정 전 — 비대화형 시작이 맞춤을 기다리는 동안 포함)에만
        // 오므로 오는 대로 건다.
        adviceSink = opened.framingAdvice
            .compactMap { $0 }
            .sink { [weak self, weak opened] advice in
                guard let self, let opened, let device = self.device else { return }
                opened.applyFramingZoom(device: device, advice: advice)
            }

        queue.async { [captureSession] in captureSession.startRunning() }
        session = opened
    }
}

/// SDK 프리뷰 뷰에 **앱의** 촬영 세션을 그리고, 세션에 붙여 가이드 · 표시 맞춤을 받는다.
private struct CustomWayPreview: UIViewRepresentable {
    let captureSession: AVCaptureSession
    let session: VultusCustomSession
    /// 프리뷰 뷰가 생기면 받는다.
    var onView: (VultusPreviewView) -> Void = { _ in }
    /// 프리뷰 뷰가 쓰는 좌표 변환이 바뀌면 받는다 — 표시 맞춤이 프리뷰를 늘리고 옮기므로 오버레이는 이 변환을 써야 한다.
    var onTransform: (VultusPreviewTransform) -> Void = { _ in }

    func makeUIView(context: Context) -> VultusPreviewView {
        let view = VultusPreviewView()
        view.fill = .fill
        // 얼굴을 보일 자리 — Default 길 예제와 같게 프리뷰 폭의 65 %, 가운데.
        view.faceGuide = VultusFaceGuide(widthFraction: 0.65, center: CGPoint(x: 0.5, y: 0.5))
        // 맞추는 동안 얼굴이 렌즈 중심에서 벗어나면 SDK 의 기본 crosshair(목적지점 + · 현재 지점 ×)를 띄운다.
        view.showsFramingCrosshair = true
        view.onTransformChange = { transform in DispatchQueue.main.async { onTransform(transform) } }
        view.attach(captureSession: captureSession)
        session.attachPreview(view)
        onView(view)
        // 분석이 프리뷰와 다르게 서면(기기를 눕혔을 때) 오버레이 변환이 그 차만큼 돌도록 실제 회전을 넘긴다.
        context.coordinator.orientation = session.effectiveOrientation
            .receive(on: DispatchQueue.main)
            .sink { [weak view] in view?.setEffectiveOrientation($0) }
        return view
    }

    func updateUIView(_ uiView: VultusPreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: VultusPreviewView, coordinator: Coordinator) {
        // 세션은 여기서 떼지 않는다 — 카메라를 멈추는 쪽(`close`)이 멈춘 뒤에 뗀다.
        coordinator.orientation = nil
    }

    final class Coordinator {
        var orientation: AnyCancellable?
    }
}
