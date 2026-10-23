import SwiftUI
import Vultus

@main
struct VultusSampleApp: App {

    /// 초기화 실패 사유. 성공했으면 nil.
    ///
    /// **초기화 실패는 앱이 반드시 다뤄야 하는 지점이다.** 실패하면 SDK 는 아무것도
    /// 하지 않고, `Vultus.current` 처럼 인스턴스를 꺼내는 접근은
    /// 초기화되지 않은 상태에서 앱을 멈춘다. 그래서 화면을 그리기 전에 여기서 갈라야
    /// 한다 — 로그만 남기고 넘어가면 곧바로 그 접근에서 죽는다.
    private let initializationError: Error?

    init() {
        initializationError = Self.setupVultus()
    }

    var body: some Scene {
        WindowGroup {
            if let initializationError {
                PreparingView(
                    message: "SDK 초기화에 실패했습니다.\n\(initializationError)",
                    showProgress: false
                )
            } else {
                ContentView()
            }
        }
    }

    /// 얼굴 검출은 Vision(시스템 프레임워크)으로 고정돼 있어 고를 것이 없다.
    /// - Returns: 실패 사유. 성공이면 nil.
    @MainActor
    private static func setupVultus() -> Error? {
        do {
            try Vultus.Initializer(
                licenseCode: Secrets.licenseCode,
                holderKey: Secrets.holderKey,
                clientKey: Secrets.clientKey
            )
            // 측정 시작 전에도 얼굴을 검출한다. 기본값(false)이면 bbox 가 안 보여
            // 자세와 거리를 잡을 수가 없다.
            .alwaysDetect(true)
            .enableFER(true)
            .initialize()
            return nil
        } catch {
            print("[VultusSample] 초기화 실패: \(error)")
            return error
        }
    }
}

/// 발급받은 라이선스 값. 실제 앱에서는 소스에 그대로 두지 말 것.
///
/// 주의: 라이선스 검증은 앱 식별자를 함께 확인한다(코어의 PKG_NAME_MISMATCH,
/// 그리고 서버 측 검증). 이 샘플앱의 번들 ID `com.example.vultus` 가 등록된
/// 라이선스 값을 넣어야 한다. 번들 ID 를 바꾸면 검증이 실패한다.
enum Secrets {
    static let licenseCode = "<licenseCode>"
    static let holderKey = "<holderKey>"
    static let clientKey = "<clientKey>"
}
