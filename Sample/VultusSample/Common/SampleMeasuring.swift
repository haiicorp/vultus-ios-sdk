import Combine
import Foundation
import Vultus

/// **세션의 스냅숏을 SwiftUI 가 쓸 수 있는 모양으로 받는다.**
///
/// SDK 는 스냅숏(상태 · 진행 · 안내 · BPM · 맞춤을 한 순간의 값으로)과 빠른 값(그래프 · 표정)을 publisher 로 낸다. SwiftUI 뷰가 값을 바로
/// 읽으려면 `@Published` 가 필요하다 — 이 객체가 그 사이를 잇는다. **어느 길의 세션을 넘길지는 각 길의 화면이 정한다**(`bind`). 세션을
/// 열기 전에 만들어도 되고, 그동안은 초기 스냅숏을 그린다.
///
/// 측정의 결말도 여기서 요약 한 줄로 바꾼다(`show`).
///
/// ⚠️ **30Hz 로 바뀌는 값은 여기 두지 않는다** — 얼굴은 [SampleFaceState], 그래프 신호는 [signal]([SampleSignalState]). 이
/// 객체에 얹으면 이것을 보는 화면 전체가 30Hz 로 다시 그려지고, 그러면 터치가 유실된다.
@MainActor
final class SampleMeasuring: ObservableObject {

    /// 한 순간의 세션 상태.
    @Published private(set) var snapshot = VultusSnapshot()
    /// 그래프 신호 — 따로 관찰한다(그래프만 본다).
    let signal = SampleSignalState()
    /// 자동 맞춤이 끝났을 때 걸린 줌.
    @Published private(set) var framingZoom: CGFloat?

    /// 측정 중 표정. 측정 상태가 바뀌면 지운다 — 지우지 않으면 측정이 끝난 뒤에도 마지막 값이 화면에 남고, 다음
    /// 측정에서는 첫 FER 결과가 올 때까지 **옛 측정의 표정**을 보여준다.
    @Published private(set) var emotion: VultusEmotionResult?
    /// 측정 결과 요약 한 줄 — 시작 거절 · 전송 완료 · 취소 · 실패가 모두 여기로 모인다.
    @Published var resultSummary: String?

    var state: VultusMeasureState { snapshot.state }
    var progress: VultusMeasureProgress { snapshot.progress }
    var signalClarity: VultusSignalClarity { snapshot.signalClarity }
    var guidance: VultusGuidance { snapshot.guidance }
    var displayBpm: VultusDisplayBpm { snapshot.displayBpm }
    /// 비대화형 시작의 카운트다운(남은 초) — 맞춰져 측정 시작을 기다리는 동안만 있다.
    var countdown: Int? {
        if case let .countdown(left) = snapshot.framing { return left }
        return nil
    }

    private var pump = Set<AnyCancellable>()

    /// 세션을 잇는다 — 스냅숏 하나와 빠른 값 둘.
    func bind(_ session: any VultusSession) {
        pump.removeAll()
        session.snapshot.sink { [weak self] next in
            guard let self else { return }
            if next.state != snapshot.state { emotion = nil }
            if case let .framed(zoom, _) = next.framing { framingZoom = zoom }
            snapshot = next
        }.store(in: &pump)
        session.signalTrace.sink { [weak self] in self?.signal.samples = $0 }.store(in: &pump)
        session.emotion.compactMap { $0 }.sink { [weak self] in self?.emotion = $0 }.store(in: &pump)
    }

    /// 응답을 요약 한 줄로 — 메인 밖에서 돈다(`nonisolated` 비동기 함수).
    private nonisolated static func summary(ofResponse json: String?) async -> String {
        VultusAnalysisResult.from(json: json).map { result in
            let hrv = "HRV 수신 — 시간 \(result.hrv.timeDomain.count) · "
                + "주파수 \(result.hrv.freqDomain.count) · 파생 \(result.hrv.derivedData.count)"
            // 분석이 무엇을 얼마나 썼는가. 구 서버 응답이면 없다.
            guard let analysis = result.analysis else { return hrv }
            let seconds = String(format: "%.1f", analysis.analyzedSeconds)
            let coverage = String(format: "%.0f", analysis.coverage * 100)
            // 박동 시각 신뢰 판정. false 여도 HRV 값은 온다 — 참고치로 표시한다.
            let trust = analysis.hrvReliable.map { $0 ? " · HRV 신뢰" : " · HRV 참고치(신뢰 미달)" } ?? ""
            return hrv + "\n분석 \(seconds)초 · 커버리지 \(coverage)%" + trust
        } ?? errorSummary(json)
    }

    /// 결과가 아니면 오류 JSON 의 `error_code` 를 보인다. 제출은 다시 보내지 않으니 다시 측정을 안내하되(가이드 9.3), 서버 인증서를
    /// 믿을 수 없으면(측정 결과 제출 `API_TLS_UNTRUSTED` · 보내기 전 라이선스 검사 `TLS_UNTRUSTED`) 같은 네트워크에서 다시 측정해도 같으므로 네트워크를
    /// 바꾸도록 안내한다(가이드 9.4).
    private nonisolated static func errorSummary(_ json: String?) -> String {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["error_code"] as? String, !code.isEmpty else { return "응답 파싱 실패" }
        if code == "API_TLS_UNTRUSTED" || code == "TLS_UNTRUSTED" {
            return "결과를 받지 못했습니다 — \(code) (네트워크 로그인을 마치거나 다른 네트워크에서 다시 측정하세요)"
        }
        return "결과를 받지 못했습니다 — \(code) (다시 측정하세요)"
    }

    /// 측정의 결말(`startMeasure` 가 돌려준 값)을 요약 한 줄로.
    func show(_ outcome: VultusMeasureOutcome) {
        switch outcome {
        case let .finished(responseJSON):
            // 응답 JSON 은 클 수 있어 메인 밖에서 파싱한다 — 메인에서 파싱하면 그동안 화면이 멈춘다. 화면 값만 메인에서 쓴다.
            Task { resultSummary = await Self.summary(ofResponse: responseJSON) }
        case .canceled:
            resultSummary = "측정이 취소되었습니다."
        // 사용자 취소와는 다른 경로다. VultusMeasureFailureReason 은 앞으로 늘어날 수 있으므로 @unknown default 로 받는다.
        case let .failed(reason, _):
            switch reason {
            case .unsupportedPixelFormat:
                resultSummary = "카메라 픽셀 포맷이 잘못됐습니다 (FullRange 필요)."
            case .cameraMismatch:
                resultSummary = "측정 중 프레임을 공급하는 카메라가 바뀌었습니다."
            case .measurementTooShort:
                resultSummary = "측정 길이를 채우지 못해 전송하지 않았습니다."
            @unknown default:
                resultSummary = "측정에 실패했습니다 — \(reason)"
            }
        // 시작하지 않았다 — 측정이 아예 돌지 않았으므로 사유를 그대로 보인다. 라이선스 거절이면 그 사유도 붙인다.
        case let .refused(error):
            resultSummary = "측정을 시작하지 못했습니다 — code \(error.rawValue) \(error == .licenseInvalid ? Vultus.license.error ?? "" : "")"
        }
    }
}

/// 얼굴 검출만 따로 든다. **매 검출 프레임(30Hz)마다 바뀌는 값**이라 이것을 보는 뷰는
/// 화면 전체가 아니라 오버레이 · 지표처럼 작은 조각이어야 한다.
@MainActor
final class SampleFaceState: ObservableObject {
    @Published private(set) var face: VultusDetectedFace?
    /// 오버레이 좌표에 거는 회전. 분석이 화면과 다르게 섰을 때(얼굴로 맞췄거나 방향을 못 박았을 때) 0 이 아니다.
    @Published private(set) var overlayRotationDegrees = 0
    /// SDK 촬영 조건의 원인 — 얼굴 색을 정한다([FaceSizeTarget]).
    @Published private(set) var captureCause: VultusCaptureCondition.Cause = .none

    private var pump = Set<AnyCancellable>()

    /// 세션을 잇는다 — 얼굴과 스냅숏의 두 필드(투영).
    func bind(_ session: any VultusSession) {
        pump.removeAll()
        session.detectedFace.sink { [weak self] in self?.face = $0 }.store(in: &pump)
        session.effectiveOrientation
            .map { $0?.overlayRotationDegrees ?? 0 }
            .removeDuplicates()
            .sink { [weak self] in self?.overlayRotationDegrees = $0 }
            .store(in: &pump)
        session.captureCondition
            .map(\.cause)
            .removeDuplicates()
            .sink { [weak self] in self?.captureCause = $0 }
            .store(in: &pump)
    }
}

/// 그래프 신호만 따로 든다. **측정 중 매 프레임(30Hz) 바뀌는 값**이라 그래프만 이것을 본다.
@MainActor
final class SampleSignalState: ObservableObject {
    @Published fileprivate(set) var samples: [Float] = []
}
