# Vultus SDK Guide for iOS

> **SDK Version**: `v1.0.0` (Swift Package)

Vultus SDK는 카메라 프레임을 기반으로 비접촉 rPPG(remote Photoplethysmography, 원격 맥박 측정) 및 FER(Facial Expression Recognition, 감정 분석) 생체 신호를 실시간 추론 및 측정합니다.

> [!IMPORTANT]
> **iOS 15 이상**, **실기기 전용**입니다. 시뮬레이터에는 카메라가 없어 측정이 불가능합니다.
> 앱 빌드에는 **Xcode 27 이상**이 필요합니다 — SDK 는 그 Xcode 로 구운 사전 빌드 프레임워크입니다.
> 시뮬레이터 슬라이스는 Apple Silicon(arm64)만 제공하며 빌드 확인 용도입니다 — Intel Mac 은 지원하지 않습니다.

---

## 📋 목차
1. [개요 및 시스템 아키텍처](#1-개요-및-시스템-아키텍처)
2. [프로젝트 설정 및 의존성](#2-프로젝트-설정-및-의존성)
3. [SDK 초기화 (Initialization)](#3-sdk-초기화-initialization)
4. [카메라와 프리뷰 — 두 길 (Default / Custom)](#4-카메라와-프리뷰--두-길-default--custom)
5. [측정 라이프사이클](#5-측정-라이프사이클)
6. [상태 구독](#6-상태-구독)
7. [프리뷰와 오버레이](#7-프리뷰와-오버레이)
8. [얼굴 검출 (Face Detection)](#8-얼굴-검출-face-detection)
9. [라이선스 검증 및 예외 처리 (License & Error Handling)](#9-라이선스-검증-및-예외-처리-license--error-handling)
10. [샘플 앱 구동 방법 (Sample App Guide)](#10-샘플-앱-구동-방법-sample-app-guide)
11. [모범 사례 및 트러블슈팅](#11-모범-사례-및-트러블슈팅)
12. [앱 스토어 제출 — 수출 규정 신고](#12-앱-스토어-제출--수출-규정-신고)

---

## 1. 개요 및 시스템 아키텍처

| 컴포넌트 | 역할 및 설명 |
| :--- | :--- |
| **`Vultus`** | SDK 의 진입점. 초기화 · 라이선스 · 세션 열기(`openDefaultSession` · `openCustomSession`) |
| **`VultusSession`** | 두 길의 세션이 공통으로 내는 것(측정 · 관찰 · 공통 override)을 묶은 프로토콜 |
| **`VultusDefaultSession`** | **Default 길 세션.** SDK 가 카메라 · 프리뷰 · 자동 맞춤을 쥡니다 |
| **`VultusCustomSession`** | **Custom 길 세션.** 앱이 카메라를 쥐고 프레임만 넘길 때 씁니다 |
| **`VultusSnapshot`** | 한 시점의 세션 상태(상태 · 진행 · 안내 · 표시 BPM · 맞춤 …) |
| **`VultusPreviewView`** | 프리뷰 표시. 표시 미러 · 종횡비 · 얼굴 가이드 · 좌표 변환 |

측정과 상태는 **두 길이 같은 것을 냅니다** — 두 세션 타입이 `VultusSession` 한 벌로 내므로 길에 따라 동작이 갈리지 않습니다. 어느 길을 고르든 §5 · §6 은 그대로 적용됩니다. 화면 조각을 두 길에서 함께 쓰려면 `any VultusSession` 으로 받으세요.

데이터 흐름은 다음과 같습니다.

| 단계 | 형태 |
| :--- | :--- |
| 프레임 입력 | `CMSampleBuffer` (2-plane full-range YUV, stride 있음) |
| 상태 전파 | Combine publisher (`session.snapshot` · `detectedFace` …) |
| 얼굴 검출 | Vision(시스템 프레임워크). SDK 내장이며 교체 대상이 아닙니다 ([8절](#8-얼굴-검출-face-detection)) |
| 좌표 변환 | SDK 가 냅니다 ([7절](#7-프리뷰와-오버레이)) |

---

## 2. 프로젝트 설정 및 의존성

### 2.1 Swift Package 추가

Swift Package Manager 로 저장소 URL 을 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/haiicorp/vultus-ios-sdk", exact: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Vultus", package: "vultus-ios-sdk")
    ])
]
```

> [!IMPORTANT]
> 버전에 `-alpha` · `-beta` 같은 접미사가 붙어 있으면 **`from:` 은 이 버전을 잡지 못합니다.** SPM 은 `from:` · `upToNextMajor` 범위에서 프리릴리스를 제외하기 때문입니다. 위처럼 `exact:` 로 못박으세요. 접미사가 없는 정식 버전에서는 `from:` 을 써도 됩니다.

Xcode 에서는 **File → Add Package Dependencies…** 에 같은 URL 을 넣고 버전을 고르면 됩니다.

`Vultus.xcframework` 는 저장소가 아니라 **릴리스 자산**으로 배포되며, SPM 이 자동으로 내려받습니다. 저장소 자체에는 바이너리가 들어 있지 않으므로 clone 이 가볍습니다.

다운로드가 실패하면 사내 프록시나 방화벽이 **GitHub 릴리스 자산 다운로드**(`github.com` 의 `/releases/download/…` 와 그 리다이렉트 대상)를 막고 있는지 확인하세요. 저장소 clone 은 되는데 프레임워크만 못 받는 경우가 이 증상입니다. 그 주소를 허용 목록에 넣거나, 열 수 없는 환경이라면 HAII 에 문의해 주세요.

### 2.2 패키지 구성

| 경로 | 내용 |
| :--- | :--- |
| `Vultus.xcframework` | SDK 전체를 담은 사전 빌드 동적 프레임워크. 공개 API 선언과 개인정보 보호 매니페스트(`PrivacyInfo.xcprivacy`)가 들어 있습니다 |
| `Sample/` | 독립 실행 가능한 샘플앱 ([10절](#10-샘플-앱-구동-방법-sample-app-guide)) |
| `README.md` | 이 문서 |
| `LICENSE` · `THIRD-PARTY-NOTICES.txt` | SDK 이용 조건과 포함된 오픈소스의 고지 ([2.6](#26-이용-조건--오픈소스-고지)) |

슬라이스는 실기기(`ios-arm64`)와 Apple Silicon 시뮬레이터(`ios-arm64-simulator`) 둘입니다.

카메라 영상 · 얼굴 이미지는 기기를 떠나지 않습니다. 나가는 것은 측정 중 영상과 센서에서 뽑은 값이며, Vultus 서버 한 곳으로만 암호화해 전송되고 서버에 저장되지 않습니다.

개인정보 보호 매니페스트(`PrivacyInfo.xcprivacy`)가 패키지에 포함되어 있어 앱 번들에 자동으로 실립니다. Apple 은 요청 처리에만 쓰고 저장하지 않는 데이터를 「수집」으로 보지 않으므로 **매니페스트의 수집 항목(`NSPrivacyCollectedDataTypes`)은 비어 있고**, App Store Connect 의 개인정보 답변에도 SDK 몫은 없습니다. 소비자 앱은 **앱이 직접 수집하는 항목만** 자기 매니페스트와 답변에 넣으면 됩니다. `appendix` 로 넘기는 값이 있다면 그것은 앱의 신고 대상입니다.

측정 데이터를 서버에 저장해야 한다면 신고가 달라집니다. 저장은 별도 협의 대상이며, HAII 에 문의하면 그에 맞는 신고 · 개인정보 보호 안내를 따로 드립니다.

### 2.3 권한 설정 (`Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>심박 측정을 위해 카메라를 사용합니다.</string>
```

### 2.4 링크 설정

시스템 라이브러리(`z`, `c++`)는 SDK 프레임워크가 직접 링크합니다. 별도 설정이 필요 없습니다.

### 2.5 버전 판올림

`Package.swift`(또는 Xcode 의 Package Dependencies)의 버전 지정을 새 버전으로 바꿉니다. 실제로 바뀌었는지는 `Vultus.sdkVersion` 으로 확인합니다([3.3](#33-전역-접근자)). 이전 버전대로 동작하면 **File → Packages → Reset Package Caches** 후 다시 빌드합니다.

> [!WARNING]
> SDK 는 사전 빌드 프레임워크라 앱에서 고칠 수 없습니다. 동작을 바꿔야 한다면 `Vultus.Config` 옵션([3.1](#31-vultusconfig-옵션))으로 되는지 먼저 확인하고, 안 되면 문의해 주세요.


### 2.6 이용 조건 · 오픈소스 고지

| 파일 | 내용 |
| :--- | :--- |
| `LICENSE` | SDK 이용 조건. SDK 는 HAII 와 체결한 계약에 따라 사용합니다 |
| `THIRD-PARTY-NOTICES.txt` | SDK 바이너리에 포함된 오픈소스 소프트웨어(OpenSSL · curl · OpenCV · ONNX Runtime 등)의 고지 |

SDK 를 앱에 넣어 배포하면 이 오픈소스들도 앱과 함께 배포됩니다. **앱의 오픈소스 고지(설정 화면의 「오픈소스 라이선스」 등)에 `THIRD-PARTY-NOTICES.txt` 의 내용을 포함해야 합니다.** 내용은 SDK 버전마다 바뀔 수 있으니 판올림할 때 함께 갱신하세요.

---

## 3. SDK 초기화 (Initialization)

`Vultus.Initializer` 는 체이닝 빌더입니다. 앱 시작 시 한 번만 호출합니다.

```swift
import Vultus

@main
struct MyApp: App {
    init() { Self.setupVultus() }

    var body: some Scene {
        WindowGroup { ContentView() }
    }

    @MainActor
    private static func setupVultus() {
        do {
            try Vultus.Initializer(
                licenseCode: "<licenseCode>",
                holderKey: "<holderKey>",
                clientKey: "<clientKey>"
            )
            .enableFER(true)
            .initialize()
        } catch {
            print("Vultus 초기화 실패: \(error)")
        }
    }
}
```

### 3.1 `Vultus.Config` 옵션

| 옵션 | 타입 | 기본값 | 설명 |
| :--- | :--- | :--- | :--- |
| `alwaysDetect` | `Bool` | `false` | 측정 중이 아닐 때도 얼굴을 계속 검출할지 |
| `enableFER` | `Bool` | `false` | 표정 인식 사용 여부 |
| `ferInterval` | `TimeInterval` | `0.25` | FER 추론 사이의 최소 간격(초, 프레임 시각 기준). `enableFER(_:ferInterval:)` 로 함께 지정. 0 ~ 60 — 밖이면 그 끝으로 자르고(숫자가 아니면 기본값). 표정 추론은 심박 처리와 같은 줄에서 차례로 돌아, 추론이 느린 기기에서는 측정 프레임 처리가 함께 밀려 일부 프레임을 건너뜁니다 — 설정한 간격을 보장하지는 않습니다. `0` 이면 측정 프레임마다 추론합니다 — 저사양 기기에서는 심박 측정의 프레임 손실 · 발열로 이어질 수 있으니, 측정 품질이 먼저면 기본값을 권합니다 |
| `lockCameraOnStartMeasure` | `Bool` | `true` | 측정을 시작하기 전(`.adjustingCamera`)에 초점 · AE · AWB 를 (지원하는 기기에서) 고정. rPPG 신호 안정성에 크게 기여. 끄면 초점 고정도 함께 꺼짐 |
| `defaultTimeoutSeconds` | `Int` | `30` | 측정 결과 전송 요청의 타임아웃(초). `defaultTimeout(_:)` 로 지정. 최대 `60`, 최소 `1` |
| `useDevServer` | `Bool` | `false` | 개발 서버로 보냅니다. `useDevServer()` 로 지정. 통합 개발 · 시험용이며 **개발 서버는 정상 동작을 보장하지 않습니다**(예고 없이 멈추거나 바뀔 수 있습니다). **릴리스 빌드에서 부르면 `initialize()` 가 예외를 던집니다**([9절](#9-라이선스-검증-및-예외-처리-license--error-handling)). 서버 주소는 SDK 안에 고정돼 있어 바꿀 수 없습니다 |

> [!IMPORTANT]
> **`alwaysDetect` 는 기본값이 `false` 입니다.** 끄면 측정 시작 전에는 검출이 돌지 않아 `detectedFace` 가 계속 `nil` 이고 자동 맞춤도 돌지 않습니다(비대화형 시작이 맞춤을 기다리는 동안은 예외로 검출이 돕니다). 프리뷰에 얼굴 박스를 그려 사용자가 자세와 거리를 잡게 하려면 켜야 합니다.
>
> ```swift
> .alwaysDetect(true)
> ```
>
> 켜더라도 측정 전 프레임은 추론 큐에 들어가지 않습니다 — SDK 가 측정 상태로 막습니다. 신호가 오염되지는 않고 검출 비용만 발생합니다.
>
> 켜면 **측정 전에도 촬영 조건 안내**([6](#6-상태-구독))가 갱신됩니다 — 조명처럼 측정을 시작한 뒤에는 고칠 수 없는 것을 미리 알릴 수 있습니다.

### 3.2 워밍업(`Vultus.PrepareState`)

`initialize()` 는 **즉시 반환합니다.** 네이티브 객체 생성(ONNX Runtime 초기화·FER 모델 로드)과 라이선스 검증은 전부 백그라운드에서 진행되므로 앱 기동이 멈추지 않습니다. `ready` 가 되어야 첫 측정도 두 번째 측정만큼 빠르게 시작됩니다.

`Vultus.current` 를 비롯한 전역 접근자는 [3.3](#33-전역-접근자)에 정리돼 있습니다.

```swift
struct ContentView: View {
    @ObservedObject private var vultus = Vultus.current

    var body: some View {
        switch vultus.prepareState {
        // 라이선스 실패에서도 측정 화면을 막지 않는다 — startMeasure 가 다시 검사한다.
        case .ready, .licenseInvalid: MeasureView()
        case .preparing:              ProgressView("측정 준비 중입니다...")
        case .failed:                 Text("초기화 실패. 앱을 다시 실행해 주세요.")
        }
    }
}
```

**시작 버튼은 `prepareState` 를 관찰해 켜고 끕니다.** 버튼에는 「지금 준비됐는가」 가 아니라 **바뀌는 순간**이 필요하고, 꺼 둘 이유(준비 중 · 사용할 수 없음)를
가려 보여 줘야 하기 때문입니다. `.licenseInvalid` 에서는 켭니다 — 시작이 라이선스를 다시 검사하는 복구 경로입니다(아래 IMPORTANT). UIKit 은
`Vultus.current.$prepareState` 를 구독해 같은 판정을 씁니다.

```swift
struct StartButton: View {
    @ObservedObject private var vultus = Vultus.current
    let start: () -> Void

    var body: some View {
        Button(title, action: start)
            .disabled(!canStart)
    }

    // 라이선스 실패는 버튼을 막지 않는다 — 사유는 Vultus.license.error 로 배너에 띄운다.
    private var canStart: Bool {
        vultus.prepareState == .ready || vultus.prepareState == .licenseInvalid
    }

    private var title: String {
        switch vultus.prepareState {
        case .preparing:              "준비 중…"
        case .failed:                 "사용할 수 없음"
        case .ready, .licenseInvalid: "측정 시작"
        }
    }
}
```

| `Vultus.PrepareState` | 의미 | 권장 UI 처리 |
| :--- | :--- | :--- |
| `preparing` | 워밍업 진행 중(초기 상태) | 스피너 + "준비 중" 안내 |
| `ready` | 워밍업 완료 | 정상 측정 화면 |
| `licenseInvalid` | 워밍업은 끝났으나 라이선스 검증 실패 | **측정 화면을 그대로 노출** + 안내 배너 |
| `failed` | 네이티브 객체 생성 자체가 실패한 치명적 상태 | 오류 안내 후 앱 재실행 유도 |

> [!IMPORTANT]
> **`licenseInvalid` 에서 측정 UI 를 막지 마세요.** 대부분은 앱 기동 시점의 일시적 네트워크 단절이고, `startMeasure()` 가 진입할 때 라이선스를 한 번 더 검사합니다. 그때 통과하면 상태는 `ready` 로 되돌아갑니다. 측정 버튼을 숨기면 이 복구 경로가 아예 실행되지 않습니다.
>
> 사유는 `Vultus.license.error` 로 읽어 안내 문구에 씁니다. 여기서 끝내 실패하면 `startMeasure()` 가 `.refused(.licenseInvalid)` 로 돌아오므로([5절](#5-측정-라이프사이클)), 그때 사용자에게 알리면 됩니다.
>
> 네트워크가 아닌 사유는 다시 시도해도 같습니다. client key 가 받아들여지지 않으면 워밍업과 `startMeasure()` 모두 `.licenseInvalid` 이고, `Vultus.license.error` 는 「라이선스 설정을 받아들이지 않았다 — client key 를 확인하라」 는 사유입니다. 발급받은 client key 를 그대로 복사해 붙여넣으세요.

### 3.3 전역 접근자

초기화 뒤에는 아래 정적 프로퍼티로 SDK 에 접근합니다.

| 접근자 | 타입 | 설명 | **초기화 전 접근** |
| :--- | :--- | :--- | :--- |
| `Vultus.sdkVersion` | `String` | SDK 버전(SemVer). 원격 지원 때 함께 알려 주세요 | 정상 동작 |
| `Vultus.isInitialized` | `Bool` | `initialize()` 가 성공한 적이 있는지 | `false` |
| `Vultus.current` | `Vultus` | SDK 인스턴스. `prepareState` 관찰에 씁니다 | **앱이 멈춥니다** |
| `Vultus.defaultAnalysisWindowSeconds` | `Int` | 분석 창 기본값(유효 초) — `startMeasure` 의 `analysisWindow` | 정상 동작 |
| `Vultus.license` | `VultusLicense` | 마지막 라이선스 검사 결과 — `isValid` · `grantedFeatures` · `error` ([9절](#9-라이선스-검증-및-예외-처리-license--error-handling)) | 무효(`isValid == false`, 빈 기능 집합, `error` 는 미초기화 안내 문자열) |

> [!NOTE]
> **측정 · 상태 · 검출 결과는 세션이 냅니다.** `Vultus.openDefaultSession` · `Vultus.openCustomSession` 으로 연 세션에서 측정하고([5절](#5-측정-라이프사이클)) 상태를 구독합니다([6절](#6-상태-구독)). 초기화 전에 열면 `.notInitialized` 가 돌아옵니다.

> [!IMPORTANT]
> **인스턴스를 꺼내는 접근자(`Vultus.current`)는 초기화 전에 부르면 앱이 멈춥니다.** `Vultus.isInitialized` 로 가드하거나, 초기화 성공을 확인한 뒤에만 그 화면을 그리세요([9절](#9-라이선스-검증-및-예외-처리-license--error-handling)).
>
> 옵셔널로 열지 않은 이유는, 이 값이 비는 경우가 **`initialize()` 를 부르지 않았거나 `alreadyInitialized` 를 무시한 경우뿐**이기 때문입니다. 둘 다 코드가 틀린 것이지 앱이 겪는 상황이 아닙니다. 옵셔널이면 **실수가 조용한 no-op** 이 되어, 아무것도 하지 않은 채 측정이 도는 상태를 앱이 알아채지 못합니다.

---

## 4. 카메라와 프리뷰 — 두 길 (Default / Custom)

Vultus 는 촬영을 다루는 길을 둘로 나눠 냅니다. 길마다 세션 타입이 다르고, 측정 · 관찰 · 공통 override 는 두 타입이 같은 프로토콜(`VultusSession`)로 냅니다. 길 전용 호출은 그 세션 타입에만 있습니다.

| | Default 길 | Custom 길 |
|---|---|---|
| 한 줄 요약 | **SDK 가 대부분을 대신합니다** | **직접 구현합니다(제약 최소)** |
| 카메라 소유 | SDK | 앱 |
| 세션 | `VultusDefaultSession` | `VultusCustomSession` |
| 열기 | `Vultus.openDefaultSession(preview:selection:)` | `Vultus.openCustomSession()` |
| 프리뷰 | `VultusPreviewView` 를 놓기만 합니다 | 앱이 그리거나 `VultusPreviewView` 를 씁니다 |
| 해상도 · fps · 톤 | SDK 가 걸고, override 로 바꿉니다 | 앱이 자기 세션에 겁니다 |
| 카메라 메타 | SDK 가 늘 모읍니다 | SDK 가 늘 모읍니다 |

두 열기는 `Result` 를 돌려줍니다 — 성공하면 세션, 실패하면 `VultusError` 입니다. 다 쓴 세션은 `close()` 로 닫습니다.

> [!IMPORTANT]
> **열린 세션은 언제나 하나입니다.** Custom 세션이 열려 있으면 어느 쪽을 열든, Default 세션이 열려 있는 동안 Custom 세션을 열면 `VultusError.otherWayActive` 가 돌아옵니다. Default 세션을 새로 열면 열린 Default 세션을 넘겨받습니다([4.2](#42-default-길--vultusopendefaultsession)).
>
> **세션 참조는 앱이 쥡니다.** Custom 세션은 SDK 가 약하게 쥐므로, 앱이 참조를 놓으면 세션이 사라지고 자리가 빕니다. Default 세션은 프리뷰 뷰가 창에 붙어 있는 동안 살아 있다가 창에서 떨어지면 닫힙니다. 어느 쪽이든 측정 · 구독에 쓰려면 화면 상태(`@State`)나 화면 모델의 프로퍼티에 담아 두세요.

### 4.1 카메라 권한 — 앱이 요청합니다

Default 길에서 SDK 는 권한을 **확인만** 하고, 없으면 세션을 열지 않고 `VultusError.cameraPermissionDenied` 를 돌려줍니다. 요청은 앱이 합니다. Custom 길은 카메라를 앱이 열므로 열 때는 확인하지 않고 측정 시작에서 확인합니다 — 권한이 없으면 `startMeasure` 가 `.refused(.cameraPermissionDenied)` 를 돌려줍니다. 그래서 Custom 세션은 권한을 묻기 전에 열어 둘 수 있습니다. `Info.plist` 의 `NSCameraUsageDescription` 도 앱의 몫입니다.

> [!WARNING]
> 권한을 묻기 **전에** `Vultus.openDefaultSession` 을 부르면 그 호출은 거절로 끝나고, 나중에 사용자가 허용해도 **다시 부르는 주체가 없습니다.** 허용이 확정된 뒤에 프리뷰를 여세요.

```swift
@State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

private func requestCameraAccessIfNeeded() {
    guard !cameraAuthorized else { return }
    AVCaptureDevice.requestAccess(for: .video) { granted in
        Task { @MainActor in cameraAuthorized = granted }
    }
}
```

### 4.2 Default 길 — `Vultus.openDefaultSession`

프리뷰 뷰를 레이아웃에 놓고 `openDefaultSession` 에 넘기면 끝입니다. 카메라 선택 · 세션 구성 · 표시 미러 · 기본 얼굴 가이드는 SDK 가 정합니다.

```swift
let preview = VultusPreviewView()
preview.fill = .fill                        // 덮기(기본) 또는 .fit(레터박스)

switch Vultus.openDefaultSession(preview: preview, selection: .front) {
case .success(let opened):
    session = opened                        // 측정 · 구독에 쓰려고 참조를 담아 둡니다
case .failure(let error):
    print("세션을 열지 못했습니다 — code \(error.rawValue)")
}

// 화면을 떠날 때(선택 — 프리뷰 뷰가 창에서 떨어지면 세션이 스스로 닫힙니다)
session?.close()
```

- **새 Default 세션은 열린 Default 세션을 넘겨받습니다.** 새 화면의 열기가 옛 화면의 닫기보다 먼저 불려도 배타 규칙에 걸리지 않습니다 — SwiftUI 의 `onAppear`/`onDisappear` 순서는 믿을 것이 못 됩니다. 넘겨준 옛 세션은 닫힙니다.
- **프리뷰 뷰가 창에서 떨어지면 세션이 스스로 닫힙니다.** `close` 를 잊어도 카메라가 열린 채 남지 않습니다.
- `selection` 은 `.front`(기본) · `.back` · `.external` · `.preferExternal` 중 하나입니다. 외장(USB)은 iPadOS 17 부터만 열리고, 그 전에는 `.preferExternal` 이 전면으로 떨어집니다. 고른 카메라를 열지 못하면 `.cameraUnavailable` 입니다.

#### SwiftUI 래퍼 (예제)

> [!NOTE]
> **SDK 패키지에는 SwiftUI 의존성이 없습니다.** 아래 래퍼를 복사해 쓰세요. 배포 패키지의 `Sample/` 에 같은 역할의 래퍼가 있습니다(`VultusSample/DefaultWay/DefaultMeasureView.swift` 의 `DefaultWayPreview`).

```swift
struct CameraPreview: UIViewRepresentable {
    let camera: VultusCameraSelection
    let onOpen: (VultusDefaultSession) -> Void      // 받은 세션은 화면 상태(@State)에 담아 둡니다
    let onError: (VultusError) -> Void

    func makeUIView(context: Context) -> VultusPreviewView {
        let view = VultusPreviewView()
        view.fill = .fill
        // 다음 메인 루프에서 연다 — `makeUIView` 는 SwiftUI 가 화면을 갱신하는 도중에 불리는데, 연 세션을 화면 상태에 담으면
        // 갱신 중에 상태가 바뀌어 SwiftUI 가 경고합니다.
        DispatchQueue.main.async {
            switch Vultus.openDefaultSession(preview: view, selection: camera) {
            case .success(let session): onOpen(session)
            case .failure(let error):   onError(error)
            }
        }
        return view
    }

    func updateUIView(_ uiView: VultusPreviewView, context: Context) {}
}
```

### 4.3 Custom 길 — `VultusCustomSession`

앱이 `AVCaptureSession` 을 쥡니다. SDK 는 프레임을 받아 측정만 합니다. 남는 제약은 넷입니다 — 픽셀 포맷(2-plane full-range YUV) · 프레임은 `captureDelegate` 로 · 측정 중 해상도 · 회전 변경 금지 · 3A 락은 SDK 가 기본으로 겁니다(끄는 길은 `overrideCameraLock`). 카메라 메타는 늘 모읍니다.

```swift
let session: VultusCustomSession
switch Vultus.openCustomSession() {
case .success(let opened): session = opened     // 참조를 쥡니다 — SDK 는 세션을 약하게 쥡니다
case .failure:             return               // 초기화 전 · 다른 세션이 열려 있음(권한은 측정 시작이 봅니다)
}

output.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
]
// SDK 가 내주는 delegate 를 그대로 꽂습니다 — 앱이 프레임 어댑터를 짜지 않습니다.
output.setSampleBufferDelegate(session.captureDelegate, queue: queue)
captureSession.addOutput(output)

// 권고 캡처 설정 — 장면에 따라 바뀌는 톤 처리를 끄고, 필요한 기기에서는 영상 안정화도 끕니다.
// 세션을 연 뒤, 출력을 세션에 붙인(addOutput) 뒤 부릅니다.
Vultus.applyRecommendedCapture(device, output: output)

// 화면을 떠날 때
session.close()
```

- **권고 캡처 설정에는 출력(`output:`)을 함께 넘기고, 출력을 세션에 붙인(`addOutput`) 뒤에 부르세요.** 톤 처리는 디바이스에, 영상 안정화는
  출력의 연결에 걸립니다(필요한 기기에서만) — 출력을 주지 않거나 붙이기 전에 부르면 톤 처리만 걸리고 영상 안정화는 앱이 둔 그대로입니다.
  **Vultus 세션을 연 뒤에 부르세요** — 무엇이 걸렸는지는 지금 열린 세션의 측정에 기록됩니다.
  Default 길은 SDK 가 같은 설정을 겁니다.
  `enabled: false` 면 걸기 전 상태(안정화 모드 포함)로 되돌립니다.
- 첫 프레임을 넘기기 전에 `startMeasure` 를 부르면 `.refused(.cameraNotAttached)` 로 거절합니다 — 프레임이 캡처 연결과 함께 들어오기 시작한 뒤에 시작하세요([5절](#5-측정-라이프사이클)).
- **프레임률은 앱이 겁니다. 30 fps 고정을 권장합니다** — 활성 포맷이 30 을 지원하면 `device.activeVideoMinFrameDuration` 과 `activeVideoMaxFrameDuration` 을 모두 `CMTime(value: 1, timescale: 30)` 으로 겁니다. **구성을 확정(`commitConfiguration`)한 뒤에** 거세요 — 프리셋 · 입력이 바뀌면 기본값으로 돌아갑니다.
- 프리뷰에 `VultusPreviewView` 를 쓴다면 `session.attachPreview(view)` 로 붙이세요 — 자동 맞춤의 표시 맞춤이 걸립니다(§4.5).
- **닫은 세션은 다시 쓰지 않습니다**(두 길 공통). 닫은 세션에서 `startMeasure` 를 부르면 `.refused(.sessionClosed)` 가, `override…`(촬영 · 회전 · 락 · 맞춤) · `setFaceGuide` 를 부르면 `.sessionClosed` 가 돌아옵니다. 측정 시작을 기다리는 사이 세션을 닫아도 `.refused(.sessionClosed)` 입니다(라이선스가 무효여도 닫힘이 먼저입니다). Default 길에서는 시작을 기다리는 사이 `Vultus.openDefaultSession` 으로 새 세션을 열어도 같습니다 — 새 세션이 옛 세션을 닫기 때문입니다. 수집 중(`.started`)에 닫으면 측정을 버리고 `.canceled` 로 끝납니다. 멈춘 측정(`stopMeasure()` · 자동 정지 · 하드 종료 뒤 — `.stopped` · `.finished` · `.submitting`)은 닫아도 버리지 않고 끝까지 보내 결말을 돌려줍니다(그 사이 `beforeSubmit` 도 불립니다). 닫은 뒤 그 측정을 버리려면 닫은 핸들의 `cancelMeasure()` 를 부르거나 `startMeasure` 를 부른 `Task` 를 취소하세요. 그 밖의 호출은 닫은 세션에서 아무것도 바꾸지 않으며, 돌려주는 값은 메서드마다 다릅니다.
- **측정을 시작할 수 있는지는 `session.state` 하나로 봅니다.** `.idle` 이면 `startMeasure` 를 부를 수 있습니다 — 앞 측정은 결과(전송 응답)까지 끝났습니다. `.idle` 이 아닐 때 부르면 수집 중(`.starting` · `.adjustingCamera` · `.started`)이면 `.refused(.notAllowedWhileMeasuring)`, 정리 · 전송 중(`.stopped` · `.finished` · `.submitting` · `.canceled`)이면 `.refused(.processingPreviousMeasurement)` 입니다.
- **예외는 세션을 닫고 곧바로 새 세션을 연 때 하나입니다.** 새 세션은 처음부터 `.idle` 이지만, 닫은 세션의 측정이 아직 정리 · 전송 중이면 `.refused(.processingPreviousMeasurement)` 가 돌아옵니다 — 결과를 보내는 중이면 전송이 끝날 때까지(전송 타임아웃 `defaultTimeoutSeconds`, 기본 30초 — 서버가 세션을 다시 요구한 드문 경우는 라이선스 재확인 약 5 초와 두 번째 전송만큼 더) 이어질 수 있습니다. 측정 화면은 결과를 받은 뒤에 닫는 것을 권합니다. 곧바로 다시 시작해야 한다면 그 시간을 덮게 재시도하세요.

  ```swift
  var outcome = await session.startMeasure(analysisWindow: analysisWindow, appendix: appendix)
  var retries = 0
  while case .refused(.processingPreviousMeasurement) = outcome, retries < 60 {
      retries += 1
      try? await Task.sleep(nanoseconds: 500_000_000)
      outcome = await session.startMeasure(analysisWindow: analysisWindow, appendix: appendix)
  }
  ```

> [!NOTE]
> **iOS 에는 `attachCamera` 가 없습니다.** SDK 가 프레임의 `AVCaptureConnection` 에서 디바이스를 얻으므로, 다른 카메라를 등록하는 사고가 구조적으로 없습니다. 시작 대기(`.starting`)부터 측정이 끝날 때까지 캡처 입력을 다른 카메라로 바꾸면 측정이 `.cameraMismatch` 로 끝나니, 카메라는 측정을 시작하기 전이나 끝난 뒤에 바꾸세요.

### 4.4 촬영 설정 override

권장값을 벗어나야 할 때 씁니다. **메서드 이름에 `override` 가 들어갑니다** — 부를 때마다 눈에 띄도록 한 것입니다.

```swift
// 두 길 공통(VultusSession)
session.overrideCameraLock(false)

// Default 길 전용(VultusDefaultSession) — 세션을 연 뒤에 부릅니다
defaultSession.overrideResolution(CMVideoDimensions(width: 1280, height: 720))  // nil 이면 권장값
defaultSession.overrideFrameRate(30)
defaultSession.overrideToneAndNoiseProcessing(false)
```

| override | 세션 | 바꾸는 것 |
| :--- | :--- | :--- |
| `overrideCameraLock` | 두 길 | 측정 시작 전(`.adjustingCamera`)의 3A 락 |
| `overrideOrientationPolicy` | 두 길 | 방향을 정하는 방식([7.2](#72-좌표-변환)) |
| `overrideResolution` · `overrideFrameRate` · `overrideToneAndNoiseProcessing` | Default 길 | SDK 가 쥔 카메라의 촬영 구성 |
| `overrideAutoFraming` | Custom 길 | 자동 맞춤의 권고([4.5](#45-자동-맞춤--사용자는-편한-자리에-카메라가-맞춥니다)) |

> [!WARNING]
> **신호 품질이 떨어질 수 있습니다.** 권장값은 측정 신호를 기준으로 정한 것이고, 바꾸면 그만큼 결과가 나빠질 수 있습니다. 그래서 **어느 축을 바꿨는지와 실제로 적용된 값이 측정에 함께 기록됩니다.**

- **측정을 시작한 뒤에는 거절합니다**(`.notAllowedWhileMeasuring`) — 시작을 기다리는 동안부터 남은 프레임을 다 처리할 때까지입니다. 해상도나 fps 가 바뀌면 한 측정 안에서 좌표계와 시계가 두 벌이 됩니다.
- **기본 프레임률은 30 fps 고정입니다.** 어두워도 fps 를 낮추지 않습니다 — 조도가 부족하면 촬영 조건이 `.tooDark` 를 내므로 사용자를 밝은 곳으로 안내하세요. 활성 포맷이 30 을 지원하지 않으면 걸지 않습니다.
- ⚠️ **활성 포맷이 지원하지 않는 프레임률은 `.unsupportedValue` 로 거절하고 권장 기본값을 그대로 씁니다**(해상도를 못 박았으면 그 크기의 포맷 가운데 하나라도 지원하면 받고, 그 포맷으로 다시 구성합니다). 받아들인 프레임률이라도 **뒤이어 해상도를 바꿔(되돌리기 포함) 새 크기의 포맷이 그 프레임률을 내지 못하면 기본값(30)으로 돌아갑니다** — 해상도와 프레임률을 함께 쓰면 해상도를 먼저 거세요. 지원하지 않는 값을 그대로 걸면 기기가 다른 센서 구성(화각)으로 갈 수 있기 때문입니다. **거절된 호출은 아무것도 바꾸지 않습니다.** 기본값으로 되돌리려면 `nil` 을 넘기세요.
- **override 는 세션의 것입니다.** 새로 연 세션은 권장값에서 시작합니다.
- **해상도 · fps · 톤 처리 override 는 Default 세션에만 있습니다.** Custom 길은 카메라를 앱이 쥐므로 그 축은 앱이 자기 `AVCaptureDevice` 에 겁니다.

### 4.5 자동 맞춤 — 사용자는 편한 자리에, 카메라가 맞춥니다

측정 전 프리뷰에서 SDK 가 두 가지를 맞춥니다. **분석 프레임의 얼굴**이 측정에 필요한 크기(얼굴 긴 변 px) 이상이 되도록 카메라 줌을, **화면의 얼굴**이 앱이 정한 자리(가이드)에 보이도록 프리뷰의 배율 · 이동을 맞춥니다. 사용자에게는 편한 거리에서 카메라를 바라보라고만 안내하면 되고, 카메라로 더 맞출 수 없을 때만 SDK 가 요청할 것을 알려 줍니다. 사람이 움직이는 동안에는 확대하지 않고 멈추면 맞춥니다. 다가와 얼굴이 커지면 멈추기를 기다리지 않고 줌을 풉니다. 맞춤이 언제 멈추는지는 측정을 시작하는 방식이 정합니다([5](#5-측정-라이프사이클) 「시작 방식」).

> [!IMPORTANT]
> 자동 맞춤은 측정 전 프리뷰의 얼굴 검출로 돕니다 — **`alwaysDetect(true)` 를 켜야 합니다.** 끄면 측정 전에는 검출이 돌지 않아 맞춤 상태가 `.searching` 에 머물고 권고도 오지 않습니다(비대화형 시작이 맞춤을 기다리는 동안은 예외로 검출이 돕니다).

**Default 길 — 가이드만 정합니다.**

```swift
// 세션을 연 뒤에 정합니다(§4.2). 범위 밖이면 .unsupportedValue 를 돌려줍니다.
session.setFaceGuide(VultusFaceGuide(widthFraction: 0.6, center: CGPoint(x: 0.5, y: 0.5)))

cancellable = session.framing.sink { state in
    switch state {
    case .framed:                 hideHint()   // 시작 버튼은 막지 않습니다 — 누르는 순간 맞춤이 멈춥니다
    case .limited(.tooFar):       showHint("조금 더 가까이 와 주세요")
    case .limited(.tooClose):     showHint("조금 더 멀리 떨어져 주세요")
    case .limited(.offCenter):    showHint("화면 가운데로 와 주세요")
    case .searching, .adjusting:  break   // 얼굴을 기다림 · 맞추는 중 — 사용자에게 할 말이 없음
    case .countdown:              break   // 비대화형 시작의 카운트다운(§5) — 대화형에서는 오지 않음
    }
}
```

- 가이드는 **프리뷰 뷰 기준 비율**입니다(화면 기준이 아닙니다). 부르지 않으면 가로 60 %, 가운데에서 조금 아래입니다. `VultusFaceGuide` 의 기본 중심은 가운데라, 폭만 넘기면 중심도 가운데로 바뀝니다. 폭은 0 초과 1 이하, 중심은 0 ~ 1 이고 밖이면 `.unsupportedValue` 입니다. 지금 가이드는 `session.faceGuide` 로 읽습니다.
- `framing` 은 **상태의 종류가 바뀔 때만** 발행합니다(`.limited` 는 이유가, `.countdown` 은 남은 초가 바뀔 때도 냅니다. `.framed` 의 값만 바뀐 것은 다시 내지 않습니다) — SwiftUI 에서 최상위로 관찰해도 화면을 매 프레임 다시 그리지 않습니다.
- 맞추는 동안 촬영 조건의 원인은 `.framing` 입니다 — 사용자에게 알릴 것이 없다는 뜻입니다. `.tooFar` 는 줌으로 더 맞출 수 없을 때만 나옵니다.
- 프리뷰를 늘리고 옮기므로, 오버레이는 반드시 `onTransformChange` 로 받은 변환을 쓰세요(§7.2).
- **프리뷰가 얼굴을 따라가는 데는 한계가 있습니다.** 얼굴이 렌즈 중심(분석 프레임 가운데)에서 멀면 화면은 일부만 옮겨, 얼굴이 가이드에서 비켜 보입니다 — 사용자가 가운데로 오게 하는 단서입니다. 맞춘 뒤 사용자가 자리를 옮기면, 멈춘 뒤 프리뷰가 다시 따라갑니다(움직이는 동안은 따라가지 않습니다). 렌즈 중심을 화면에 보이려면 맞춤 crosshair 를 켜세요(§7.4).
- **가이드가 프리뷰 모양에 비해 작으면 프리뷰 가장자리가 빕니다(레터박스).** 가이드는 프리뷰 뷰 기준이고 측정에 필요한 얼굴 크기는 분석 프레임 기준이라, 프레임 일부가 잘려 보이는 프리뷰(세로로 긴 전체 화면 등)에서는 얼굴을 가이드에 얹으려고 영상을 덮기보다 작게 그립니다. 빈 가장자리가 싫으면 프리뷰 뷰를 분석 프레임에 가까운 비율로 두거나 가이드를 키우세요.
- **Default 길에서는 늘 켜져 있습니다** — 카메라를 SDK 가 쥐므로 끄는 메서드가 없습니다. 맞춤 없이 카메라를 다루려면 Custom 길을 쓰세요.

**Custom 길 — SDK 는 앱의 카메라를 바꾸지 않습니다.** 프리뷰 표시는 `VultusPreviewView` 를 쓰면 SDK 가 맞추고, 줌은 SDK 의 권고를 받아 앱이 겁니다.

```swift
previewView.faceGuide = VultusFaceGuide(widthFraction: 0.6, center: CGPoint(x: 0.5, y: 0.5))
previewView.attach(captureSession: captureSession)
session.attachPreview(previewView)            // 가이드 · 표시 맞춤 · 오버레이 변환을 세션에 잇는다

// 권고는 줌을 바꿔도 되는 때(측정 전 — 비대화형 시작이 맞춤을 기다리는 동안 포함)에만 옵니다 — 오는 대로 겁니다.
adviceCancellable = session.framingAdvice
    .compactMap { $0 }
    .sink { [weak session] advice in
        guard let session else { return }
        session.applyFramingZoom(device: device, advice: advice)   // 선택 — 줌을 바꾸면 안 되는 때면 걸지 않고 false
        if let limit = advice.limit { showHint(limit) }            // 줌으로 더 맞출 수 없을 때 사용자에게 요청할 것
    }

// 화면을 떠날 때 — close() 도 표시 맞춤을 뗍니다
session.attachPreview(nil)
// 영상 층의 세션은 앱이 카메라를 멈춘 **뒤에** 뗍니다 — 층의 세션을 바꾸는 일도 세션 구성이라 `stopRunning` 과 겹치면 앱이 끝납니다
queue.async {
    captureSession.stopRunning()
    DispatchQueue.main.async { previewView.attach(captureSession: nil) }
}
```

- 권고 줌(`recommendedZoomFactor`)은 **센서의 실제 화소를 더 쓰는 범위까지만** 나옵니다 — 그 이상 확대해도 측정 품질은 좋아지지 않습니다. 권고의 `targetFaceBoxPx` 는 맞추려는 얼굴 크기, `currentFaceBoxPx` 는 지금 크기(분석 프레임의 얼굴 긴 변 px)입니다.
- **줌은 권고가 올 때만 거세요.** 권고는 측정 중에는 `nil` 이고, `applyFramingZoom` 도 그때는 걸지 않습니다. 실제 줌은 프레임마다 측정에 기록됩니다. **측정 중에는 해상도를 바꾸지 마세요.**
- **권고를 따를지는 앱이 정합니다.** 따르지 않아도 SDK 는 그대로 동작합니다 — 측정 · 촬영 조건 판정은 권고와 무관합니다.
- **Default 길과 Custom 길이 같은 `VultusPreviewView` 를 번갈아 쓰지 마세요.** 한 길의 세션이 멈추고 떼어지기 전에 다른 길이 같은 뷰에 붙으면, 영상 층 바꾸기가 상대 세션의 시작 · 멈춤과 겹치거나 늦게 온 떼기가 새 세션을 뗍니다(닫은 Default 세션이 멈추는 동안에는 그 뷰의 붙이기 · 떼기가 멈춘 뒤로 미뤄집니다). 길마다 새 뷰를 쓰세요.
- Custom 길의 촬영 조건은 앱이 권고를 따를지 알 수 없으므로 `.framing` 대신 `.tooFar` 를 그대로 냅니다.
- 권고 줌을 걸었는데 카메라가 그 줌에 닿지 않으면, SDK 는 닿은 줌을 그 카메라의 한도로 보고 같은 줌을 거듭 권하는 대신 `limit` 로 사용자에게 요청합니다. `applyFramingZoom` 을 쓰지 않고 앱이 직접 걸어도, 줌이 권고 쪽으로 움직였으면 같게 봅니다. 한도는 맞춤을 처음부터 다시 할 때(다른 카메라 · 촬영 override 로 다시 구성 · 프리뷰를 다시 붙임 · 맞춤을 다시 켬)와 줌이 그 한도보다 올라갔을 때 풀립니다.
- 끄려면 `session.overrideAutoFraming(false)` — 권고를 멈춥니다.
- 자체 프리뷰를 쓰는 앱은 표시 맞춤 없이 권고만 받아 쓰면 됩니다.

---

## 5. 측정 라이프사이클

두 길이 같은 것을 냅니다 — 열린 세션(`VultusSession`)에서 부릅니다. 두 세션 타입(`VultusDefaultSession` · `VultusCustomSession`)은 `startMeasure` 의 모든 인자에 기본값을 둡니다. 프로토콜(`any VultusSession`)로 부를 때는 기본값이 없으므로 인자를 모두 넘깁니다.

```swift
// 측정 중 계속 오는 값은 publisher 로 읽습니다. 표정은 측정을 시작하면 nil 로 돌아갑니다.
session.emotion
    .compactMap { $0 }
    .sink { emotion in /* ... */ }
    .store(in: &cancellables)

Task {
    // 측정이 끝날 때까지 기다렸다가 결말을 돌려받습니다 — 측정 하나에 결말 하나입니다.
    switch await session.startMeasure(
        analysisWindow: 60,                 // 서버가 분석할 유효 초 — 기본 60
        appendix: ["userKey": "..."]        // 측정에 그대로 실려 서버로 갑니다
    ) {
    case .finished(let json):
        showResult(VultusAnalysisResult.from(json: json))   // 전송 단계를 끝냈습니다 — 서버 응답 또는 오류 JSON(결과가 아니면 nil, 9.3)
    case .canceled:
        showCanceled()                      // 전송 없이 끝났습니다
    case .failed(let reason, let progress):
        showFailure(reason, lastProgress: progress)              // 측정이 결과를 낼 수 없어 끝났습니다
    case .refused(let error):
        showRefusal(error)                  // 시작하지 않았습니다 — error.rawValue 로 사유를 판단합니다
    }
}

session.stopMeasure()    // 지금까지 모은 것으로 끝냅니다
session.cancelMeasure()  // 버립니다 — 전송하지 않습니다
```

`cancelMeasure()` 는 측정 취소입니다 — 결말 전이면 어느 단계에서든 측정을 버리고 `.idle` 로 돌아갑니다. 코어 측정 객체를 만들고 라이선스를 확인하는 동안(`.starting` 의 첫머리)은 끊지 않고, 그것이 끝나는 대로 버립니다. 보내는 중(`.submitting`)이면 전송을 끊고 `.canceled` 로 끝냅니다. 예외가 하나 있습니다 — 보내는 중 서버가 세션을 다시 요구하면(HTTP 401) SDK 가 라이선스를 다시 확인하는데(약 5 초), 이때 취소하면 상태는 곧바로 `.canceled` 가 되고, 그 확인이 끝나면 다시 보내지 않고 `.canceled` 결말과 함께 `.idle` 로 갑니다. 마지막 라이선스 확인 뒤 서버에서 라이선스(권한 등)가 바뀐 드문 경우입니다.

| 결말 | 뜻 |
| :--- | :--- |
| `.finished(responseJSON:)` | 전송 단계를 끝냈습니다. 서버에 닿았으면 서버 응답 JSON(파싱은 `VultusAnalysisResult.from(json:)`), 보내지 못했거나 응답을 믿을 수 없으면 SDK 가 만든 오류 JSON 입니다 — 형태와 `error_code` 는 [9.3](#93-오류-응답-json) |
| `.canceled` | 버렸습니다 — `cancelMeasure()`(보내는 중이면 전송을 끊음) · 수집 중 세션 닫기 · `beforeSubmit` 이 `nil` 을 돌려줌 · 부른 `Task` 의 취소 |
| `.failed(_:progress:)` | 측정이 진행되다 깨졌습니다(`VultusMeasureFailureReason` — `.measurementTooShort` · `.unsupportedPixelFormat` · `.cameraMismatch`). `progress` 는 끝난 측정의 마지막 진행입니다 |
| `.refused(_:)` | 시작하지 않았습니다 — 그 이유(`VultusError`) |

> [!IMPORTANT]
> **`analysisWindow` 는 서버가 분석할 길이입니다.** 서버는 받은 측정에서 정확히 이 길이(유효 초)의 구간 하나를 골라 HRV 를 계산합니다 — 세션마다 분석 길이가 같아야 SDNN 처럼 길이에 따라 달라지는 지표를 비교할 수 있습니다. 기본 60, 20 초 이상이고 상한은 174 초입니다(서버 설정에 따라 더 길 수 있습니다). 범위 밖이면 시작이 `.unsupportedValue` 로 거절됩니다.
>
> **창을 채우면 SDK 가 스스로 멈춥니다**(`extraSeconds` 기본 0). 앱이 타이머를 들 필요가 없습니다.
>
> | `extraSeconds` | 동작 |
> | :--- | :--- |
> | `0`(기본) | 창을 채우는 즉시 멈춥니다 |
> | `N` | 창을 채운 뒤 유효 신호 N 초를 더 모으고 멈춥니다 — 서버가 그 여유 안에서 분석할 구간을 고릅니다 |
> | `nil` | 자동으로 멈추지 않습니다 — 앱이 `stopMeasure()` 로 멈춥니다 |
>
> 어느 경우든 **측정 시작부터 정해진 시간(기본 180 초)에서 SDK 가 멈추고 모은 것을 보냅니다**(하드 안전 종료 — 한 측정을 한 요청으로 보내는 전송 한계입니다). 이 시간은 서버 설정에 따라 더 길 수 있고, 받을 수 있는 분석 창(기본 상한 174 초)을 채우기에 늘 충분합니다.
>
> 길이는 **벽시계가 아니라 유효 신호가 모인 시간**으로 셉니다. 얼굴을 놓친 구간은 진행에 들어가지 않습니다. **측정은 분석 창보다 몇 초 더 걸립니다** — 실제로 모으는 길이는 `progress` 의 `targetSeconds` 입니다.
>
> 결과의 `analysis.analyzedSeconds` 는 박동이 실제로 걸친 길이입니다. 신호가 깨끗하면 `analysisWindow` 와 같고, 신호가 나쁜 구간이 있으면 그만큼 짧게 나옵니다. 창을 담을 만큼 이어진 구간이 없었으면 `analysis.windowSelection` 이 `longestSegment`(가장 긴 구간 전체)로 옵니다.

> [!NOTE]
> **`.fulfilled` 는 「창을 채웠다」이지 「멈췄다」가 아닙니다.** 여기서 멈춰도 요청한 길이의 분석이 나오므로 강한 안내를 거둘 수 있는 지점입니다. 수집은 `targetSeconds` 까지 이어지므로 `progress` 의 `collectedSeconds` 는 `analysisWindow` 를 **넘습니다** — 진행바는 `percent`(수집 ÷ `targetSeconds`)로 그리세요. `targetSeconds` 는 SDK 가 스스로 멈추는 길이이고, `elapsedSeconds` 는 벽시계 시간입니다(진행은 측정 프레임을 처리할 때마다 갱신되므로 얼굴을 놓친 동안은 멈춰 있다가 따라잡습니다).

> [!NOTE]
> **HRV 가 비어 오면 `analysis.hrvUnavailable` 이 이유를 말합니다.** 서버가 박동을 세우지 못하면 `hrv` 의 세 블록이 빈 채로 정상 응답이 옵니다 — 오류가 아니라 「계산하지 못했다」는 결과입니다. 블록이 차 있으면 이 값은 `nil` 입니다.
>
> | 값 | 뜻 | 안내 예 |
> | :--- | :--- | :--- |
> | `tooShort` | 분석할 수 있는 길이가 20 초에 못 미쳤습니다 | 측정이 너무 짧습니다 |
> | `noContinuousSegment` | 길이는 됐지만 20 초 넘게 이어진 구간이 없었습니다 | 얼굴이 자주 화면을 벗어났습니다 |
> | `noPulse` | 이어진 신호는 있었는데 맥박을 찾지 못했습니다 | 조명과 자세를 확인해 주세요 |
>
> 상수는 `VultusAnalysisResult.Report.hrvTooShort` 등입니다. **값은 앞으로 늘어날 수 있으니** 모르는 값은 일반 안내로 받으세요.
>
> 측정 **중에** 앵커(연속 10 초)가 끝내 서지 않은 것은 이것과 다른 자리에서 알립니다 — `submitUnfulfilledMeasurement: false` 면 결말이 `.failed(.measurementTooShort, progress:)` 로 전송 없이 끝나고, 그때 `progress.state` 가 `.anchoring` 입니다. 보냈다면 서버가 `tooShort` · `noContinuousSegment` 로 말합니다.

> [!NOTE]
> **결말이 돌아올 때는 SDK 가 측정을 정리한 뒤입니다** — `state` 는 이미 `.idle` 이므로, 돌아온 뒤 곧바로 다음 측정을 시작해도 됩니다. 측정이 도는 동안 다시 부르면 `.refused(.notAllowedWhileMeasuring)` 입니다.
>
> 같은 이유로 결말이 돌아올 때 진행(`progress`)은 이미 초기값입니다 — **실패를 가를 진행은 `.failed` 에 실린 `progress` 로 읽으세요.** 끝난 측정의 마지막 진행입니다. `.measurementTooShort` 에서 그 `state` 가 `.anchoring` 이면 연속 10초(앵커)가 끝내 서지 않은 것이고, `.anchored` 면 앵커는 섰지만 목표 전에 멈춘 것입니다. 사용자에게 줄 안내가 다릅니다(얼굴을 화면 안에 두라 · 끝까지 기다리라).
>
> ```swift
> case .failed(.measurementTooShort, let progress):
>     showHint(progress.state == .anchoring ? "얼굴을 화면 안에 두세요" : "끝까지 기다려 주세요")
> ```
>
> **결과가 돌아오기 전에 `startMeasure` 를 부른 `Task` 가 취소되면 서버 전송도 취소되며 분석 결과를 받을 수 없습니다.** 결과가 필요한 앱은 뷰가 사라져도 취소되지 않는 `Task` 에서 부르세요(SwiftUI 의 `.task` 는 뷰가 사라지면 취소됩니다).

`startMeasure` 는 **측정이 끝날 때까지 돌아오지 않습니다** — 시작이 거절되면 곧바로 `.refused(사유)` 로, 시작했으면 측정이 끝난 뒤 결말로 돌아옵니다. 세션을 연 직후 첫 프레임이 캡처 연결과 함께 들어오기 전에 부르면 `.refused(.cameraNotAttached)` 입니다 — `effectiveOrientation` 이 값을 내면 첫 프레임이 들어와 방향이 정해진 것입니다(정해진 값만 냅니다 — 얼굴 기준(`.faceProbe`)이면 맞출 때까지 `nil` 입니다). 진행률은 `progress` 로 받으세요 — 앱이 벽시계로 세면 얼굴을 놓친 구간까지 진행으로 쳐서, 서버가 계산하지 못하는 측정을 "다 모았다" 고 표시하게 됩니다.

**시작 방식 — 대화형 · 비대화형.** `startMeasure` 의 `mode` 가 측정을 언제 시작하는지를 정합니다. **시작한 뒤의 측정은 둘이 같습니다** — 시작 순간 자동 맞춤을 멈추고 걸려 있던 줌이 닿으면 노출 · 화이트밸런스를 잠그고 수집합니다.

| | `.interactive`(기본) | `.nonInteractive(timeoutSeconds:countdownSeconds:)` |
| :--- | :--- | :--- |
| 쓰는 곳 | 사용자가 시작 버튼을 누른다 | 버튼 없이 시작한다(화면이 열리자마자 등) |
| 시작 순간 | 누른 순간 | 얼굴이 맞춰지고 줌이 닿고 사람이 멈추고 카메라 노출이 자리 잡은 뒤 카운트다운을 다 센 순간 |
| 맞춰지지 않으면 | 그대로 시작한다(얼굴 기준 방향 맞춤은 예외 — [7.2](#72-좌표-변환)) | 제한 시간 안에 카운트다운이 시작되지 않으면 시작하지 않는다(`.framingFailed`) |

```swift
// 화면이 열리자마자 — 맞춰지고 카운트다운(기본 3 초)을 센 뒤 시작합니다. 제한 시간(기본 10 초) 안에 맞춰지지 않으면 `.refused(.framingFailed)` 로 돌아옵니다
.task(id: session.map { ObjectIdentifier($0) }) {
    guard let session else { return }
    // 첫 프레임이 들어와 방향이 정해지기를 기다립니다 — 첫 프레임 전에 시작하면 `.refused(.cameraNotAttached)` 입니다.
    var decided = false
    for await orientation in session.effectiveOrientation.values where orientation != nil { decided = true; break }
    // 작업이 취소되면 흐름이 값 없이 끝납니다 — 그때는 시작하지 않습니다(SwiftUI 가 작업을 다시 띄우며 앞 작업을 취소하기도 합니다).
    guard decided, !Task.isCancelled else { return }
    show(await session.startMeasure(analysisWindow: 60, mode: .nonInteractive()))
}
```

- `timeoutSeconds` 는 첫 카운트다운이 시작되기까지 기다릴 최대 시간입니다. 주지 않으면 기본 10 초, `0` 이면 무제한, 상한은 10 초입니다.
- `countdownSeconds` 는 맞춰진 뒤 시작까지 셀 시간입니다. 주지 않으면 기본 3 초, `0` 이면 맞춰지는 즉시 시작, 상한은 5 초입니다.
- 주지 않은 값의 기본은 서버 설정에 따라 다를 수 있습니다 — 정해진 시간이 필요하면 값을 넘기세요.
- 음수이거나 상한을 넘기면 `.unsupportedValue` 로 거절합니다.
- **카운트다운은 `framing` 에 `.countdown(secondsLeft:)` 로 1 초마다 옵니다.** 세는 중 맞춤이 깨지면(움직였거나 얼굴을 놓침) 다른 상태로 바뀌고, 다시 맞춰지면 처음부터 셉니다. 제한 시간이 지난 뒤 깨지면 그때 `.framingFailed` 로 거절합니다.
- 맞춤을 기다리는 동안은 라이선스 확인 · 맞춤과 겹쳐 진행되고(`alwaysDetect` 를 끈 세션은 라이선스 확인 뒤에 맞춤을 시작합니다 — 제한 시간도 그때부터 잽니다), 이 시간은 측정 길이에 들어가지 않습니다(수집은 시작 순간부터 합니다).
- 자동 맞춤을 끈 세션(`overrideAutoFraming(false)`)에는 맞출 것이 없어, 비대화형도 곧바로 시작합니다.
- `alwaysDetect` 를 켜지 않은 세션도 비대화형 시작이 맞춤을 기다리는 동안에는 SDK 가 얼굴 검출을 돌립니다(그 밖의 측정 전에는 돌지 않습니다).
- **줌이 걸리는 중이면 다 걸릴 때까지 기다립니다.** 줌은 한 번에 걸지 않고 짧게 나눠 겁니다. 시작 순간 걸리던 줌이 다 걸린 뒤에 수집을 시작합니다(카메라가 줌에 닿지 않으면 잠시 기다린 뒤 시작합니다). 그래도 닿지 않은 채 시작했으면 시작 뒤에 닿을 때까지 줌이 마저 움직입니다.
- **측정 중 `framing` 은 거리 요청만 냅니다** — 멀면 `.limited(.tooFar)`, 가까우면 `.limited(.tooClose)`, 문제가 없으면 `.framed` 입니다. 그 뒤로 `.adjusting` · `.offCenter` 를 새로 내지 않고, 맞춤이 멈춘 순간의 상태는 다음 거리 판정까지 남습니다.


**스레드 — 무엇이 어디서 도는가.** 측정 상태와 결말은 메인 액터에 있고, 프레임 처리 · 네트워크는 SDK 가 백그라운드에서 합니다. 아래와 다르게 가정하지 마세요.

| 동작 | 스레드 | 권고 |
| :--- | :--- | :--- |
| 세션 열기 · `startMeasure(...)` · `stopMeasure()` · `cancelMeasure()` · `close()` | **메인 액터**(`@MainActor`) | 메인 밖에서는 `await` 로 부르세요. `startMeasure` 는 측정이 끝날 때까지 돌아오지 않습니다 — 버튼 액션에서는 `Task { }` 로 감싸세요 |
| 프레임 처리(검출 · 신호) | SDK 백그라운드 | 앱이 스레드를 따로 잡지 않습니다 |
| 프레임 입구 `session.captureDelegate` | 앱이 `setSampleBufferDelegate` 에 넘긴 큐 | 메인 큐는 넘기지 마세요 — 검출이 화면을 멈춥니다 |
| 라이선스 확인 · 결과 전송 | SDK 백그라운드 | — |
| `startMeasure` 가 돌려주는 결말 | **메인 액터** | 화면을 바로 갱신해도 됩니다. 결과 파싱 · 저장처럼 오래 걸리는 일은 메인 밖으로 넘기세요 |
| `beforeSubmit` 훅 | **메인 액터** | 동의 창 같은 화면을 띄울 수 있습니다. 동기로 막는 호출(파일 · 네트워크)은 훅 안에서 메인 밖으로(`Task.detached`) 옮기고, async API 는 그대로 `await` 하세요 — `await` 하는 동안에는 메인을 막지 않습니다. 훅이 도는 사이 측정을 버리면(`cancelMeasure()` · 부른 `Task` 의 취소) SDK 는 훅을 기다리지 않고 곧바로 `.canceled` 로 끝내고 훅의 작업에 취소를 건넵니다 — 띄운 창은 `.canceled` 를 받으면 닫으세요 |
| publisher(`snapshot` · `state` · `progress` · `displayBpm` · `guidance` · `emotion` …) | **메인에서 보냅니다** | `receive(on:)` 없이 화면을 갱신해도 됩니다 — 붙이면 한 턴 늦어 옛 상태로 판단할 수 있습니다. SDK 는 값을 늘 메인의 다음 차례에 냅니다 — 수집기 안에서 `close()` 같은 입구를 불러도 됩니다. 연달아 바뀌면 마지막 값만 올 수 있습니다 |

---

## 6. 상태 구독

세션이 상태를 **스냅숏**(`VultusSnapshot`) 하나로 냅니다. 상태 · 진행 · 안내 · 표시 BPM · 맞춤이 **한 순간의 값**이라, 여러 값을 함께 보는 판단(예: 상태와 진행)이 어긋나지 않습니다.

| 구독 | 내는 것 | 흐르는 때 |
| :--- | :--- | :--- |
| `session.snapshot` | `VultusSnapshot` — `state` · `progress` · `signalClarity` · `stability` · `captureCondition` · `guidance` · `displayBpm` · `framing` · `effectiveOrientation` | 구독하면 지금 값부터, 그 뒤로는 필드 하나라도 바뀔 때만 |
| `session.currentSnapshot` | 지금 스냅숏(구독 없이 읽기) | — |
| `session.state` · `progress` · `signalClarity` · `stability` · `captureCondition` · `guidance` · `displayBpm` · `framing` · `effectiveOrientation` | 스냅숏의 필드 하나(투영) | 구독하면 지금 값부터, 그 필드가 바뀔 때만 |
| `session.signalTrace` · `detectedFace` · `emotion` | 그래프 신호 · 검출된 얼굴 · 표정 | 갱신될 때마다 — 크거나 빨라 스냅숏에 넣지 않습니다 |

선언형 UI 는 스냅숏 하나를 구독하고, 위젯 하나만 갱신한다면 그 필드의 투영을 받습니다. `effectiveOrientation` 은 정해진 방향만 냅니다 — 첫 프레임 전(얼굴 기준이면 맞추기 전)은 `nil` 이고, 방향 정책이나 카메라(촬영 override 로 다시 구성 포함)를 바꾸면 곧 `nil` 이 되었다가 다시 정해지면 값이 옵니다.

```swift
session.snapshot.sink { snapshot in
    render(state: snapshot.state, progress: snapshot.progress, guidance: snapshot.guidance)
}.store(in: &cancellables)
session.displayBpm.sink { bpm in /* 화면에 띄울 BPM */ }.store(in: &cancellables)
session.detectedFace.sink { face in /* 검출된 얼굴 */ }.store(in: &cancellables)

// SwiftUI 에서는 onReceive 로 받습니다.
.onReceive(session.guidance) { guidance in /* 사용자에게 할 말 */ }
```

SwiftUI 화면 모델은 스냅숏을 `@Published` 로 옮겨 담으면 됩니다. 세션을 열기 전에는 초기 스냅숏을 그립니다(샘플의 `SampleMeasuring`).

```swift
@MainActor
final class MeasureModel: ObservableObject {
    @Published private(set) var snapshot = VultusSnapshot()
    private var cancellables = Set<AnyCancellable>()

    func bind(_ session: any VultusSession) {
        cancellables.removeAll()
        session.snapshot.sink { [weak self] in self?.snapshot = $0 }.store(in: &cancellables)
    }
}
```

**`VultusMeasureState`** 는 `idle → starting → adjustingCamera → started → stopped → finished → submitting → idle` 로 흐릅니다.

| 상태 | 뜻 | 측정 버튼 |
| :--- | :--- | :--- |
| `.idle` | 측정이 없다. **다음 측정은 여기서만 시작합니다** | 시작 |
| `.starting` | 시작이 라이선스 확인 · 준비 · 걸리던 줌 · 비대화형 시작의 맞춤과 카운트다운을 기다린다(콜드 스타트면 수 초). 거절되면 `.idle` 로 돌아갑니다 | 막아 두기(「준비 중」) |
| `.adjustingCamera` | 측정을 시작하기 전에 카메라를 고정합니다 — 초점 → 노출 → 화이트밸런스 순서로, 각각 자리를 잡은 뒤 잠급니다. 3A 락이 꺼져 있으면 거치지 않습니다 | 막아 두기(「카메라 조정 중」) |
| `.started` | 프레임을 모은다 | 멈춤 |
| `.stopped` | 새 프레임은 받지 않고, 멈추기 전에 받은 프레임을 모두 처리한다 | 막아 두기 |
| `.finished` | 보낼 결과를 만든다(`beforeSubmit` 포함) | 막아 두기 |
| `.submitting` | 결과를 서버로 보내고 응답을 기다린다. 응답이 오면 `.idle` 로 갑니다. 전송하지 않고 끝나면 거치지 않습니다 | 막아 두기(「결과 전송 중」) |
| `.canceled` | 버리고 정리한다. 결말 전 어느 단계에서든(보내는 중 `.submitting` 포함) 옵니다 | 막아 두기 |

`.starting` · `.adjustingCamera` 에서 `stopMeasure()` 를 부르면 모인 것이 없으므로 `cancelMeasure()` 와 같게 버립니다. 카메라는 측정 구간이 시작되기 **전에** 고정되므로 고정하는 동안의 변화가 측정에 섞이지 않습니다. 상태를 `switch` 로 빠짐없이 나누는 앱은 `.adjustingCamera` · `.submitting` 도 다뤄야 합니다(각각 「시작 중」 · 「전송 중」 과 같이 막아 두면 됩니다).

> [!NOTE]
> **고빈도 값은 화면 전체가 관찰하는 객체에 두지 마세요.** `detectedFace` 는 30Hz 로, `signalTrace` 는 측정 중 프레임마다 바뀝니다 — 화면 모델의 `@Published` 로 받아 최상위 뷰를 다시 그리면 그만큼 다시 그려져 터치(`Menu` · 탭 제스처)가 유실될 수 있습니다. 스냅숏에는 둘 다 없어 바뀔 때만 흐르므로 최상위에서 관찰해도 됩니다. 얼굴 · 그래프는 따로 둔 객체로 받아 오버레이 · 그래프처럼 필요한 뷰만 `@ObservedObject` 로 보세요(샘플의 `SampleFaceState` · `SampleSignalState`). 그 객체를 최상위 뷰가 `@StateObject` 로 들면 최상위도 함께 관찰하게 되므로 `@State` 로 들거나, 화면 모델의 저장 속성(`let`)으로 둡니다 — 중첩된 객체의 변경은 화면 모델로 전해지지 않습니다.

---

## 7. 프리뷰와 오버레이

### 7.1 `VultusPreviewView`

프리뷰 표시는 SDK 뷰가 맡습니다. 표시 미러 · 종횡비 · 얼굴 가이드가 이 안에서 끝납니다.

```swift
preview.fill = .fill                    // 덮기 / .fit = 레터박스
preview.guideOverlayEnabled = true      // 얼굴 가이드 점선
preview.dimsOutsideTargetRegion = false // 가이드 밖을 어둡게
```

### 7.2 좌표 변환

검출 좌표(`VultusDetectedFace.boundingBox` · 랜드마크)는 **회전 보정된 분석 프레임의 픽셀 좌표**입니다. 화면에 얹으려면 배율 · 오프셋 · 미러를 맞춰야 하는데, 그 값을 **프리뷰 뷰가 알려 줍니다.**

```swift
preview.onTransformChange = { transform in
    // 뷰 크기 · 프레임 크기 · 미러가 달라질 때마다 옵니다.
    self.overlayTransform = transform
}

// 그릴 때
let box = overlayTransform.rect(face.boundingBox)
let point = overlayTransform.point(landmark)
```

Custom 길에서는 세션에서 직접 받을 수도 있습니다.

```swift
let transform = session.previewTransform(imageSize: imageSize, viewSize: viewSize,
                                         fill: .fill, mirrored: true)
```

**방향은 정하는 방식을 고릅니다 — 대부분의 앱은 아무것도 부르지 않습니다.** 분석 프레임은 얼굴이 바로 서는 좌표계로 세워야 하고, 그 좌표계를 무엇으로 정할지가 `overrideOrientationPolicy` 입니다.

| 대상 | 부르는 것 | 방향을 정하는 것 |
|---|---|---|
| 범용 기기(스마트폰 · 태블릿) | 없음(`.default`) | 카메라 · 화면이 신고한 값(카메라 장착 + 화면 회전) |
| 신고가 맞지 않는 전용 기기 · 외장 카메라 | `.faceProbe` | 얼굴 — 얼굴이 바로 서는 회전을 프레임에서 찾습니다 |
| 〃 | `.fixed(…)` | 앱이 못 박은 장착 · 화면 방향 |

- **기본(`.default`)** — 측정 밖에서는 화면 회전을 프레임마다 따릅니다. 가로 · 세로 UI 를 모두 내는 앱도 저절로 맞고, 화면을 돌려도 세션을 다시 열 필요가 없습니다. UI 를 한 방향으로 고정한 앱에서 기기를 눕히면 프레임 속 얼굴도 누워 검출되지 않습니다 — 설계가 그렇습니다. UI 방향대로 들고 측정하세요.
- **얼굴 기준(`.faceProbe`)** — 얼굴이 바로 서는 회전을 프레임에서 찾아 맞춥니다. 찾을 때까지 주기적으로 다시 봅니다. 맞추기 전에는 `effectiveOrientation` · `detectedFace` 가 `nil` 이고, 측정 시작은 맞추기를 기다립니다 — 상한(비대화형은 시작 관문의 제한 시간, 대화형은 그 기본값)을 넘기면 `.framingFailed` 로 거절합니다. 화면이 돌면 다시 맞춥니다. 좌우 반전은 얼굴로 알 수 없으니, 프레임이 반전으로 들어오는 카메라는 `.fixed(…)` 를 쓰세요.
- **고정(`.fixed(…)`)** — 장착(`VultusCameraMounting` — 각도 · 좌우 반전)과 화면 방향을 못 박습니다. `nil` 인 것은 신고한 값을 씁니다 — 화면 방향을 OS 로 고정한 기기는 장착만 넘기면 됩니다. 분석 좌표계만 고칩니다 — 프리뷰는 `AVCaptureVideoPreviewLayer` 가 그립니다.

> [!TIP]
> **고정 거치 기기는 `.faceProbe` 로 얻은 값으로 `.fixed(…)` 로 바꾸기를 권합니다.** `.faceProbe` 는 세션마다 얼굴이 보여야 방향이 정해지고, 그때까지 측정을 시작할 수 없으며, 시도마다 검출 비용이 커 사용성이 떨어질 수 있습니다. 한 번 `.faceProbe` 로 돌려 `effectiveOrientation.cameraMounting`(얼굴로 맞춘 회전을 내는 장착 방향)을 얻고, 그 값을 `.fixed(…)` 에 하드코딩하세요. 그 장착은 **탐색할 때의 화면 방향을 기준으로** 낸 값입니다 — 장착만 넘기고 화면 방향은 신고 값에 맡기세요(화면 방향까지 못 박는다면 탐색할 때와 같은 방향이어야 합니다). 프리뷰가 서는 각을 장착으로 옮기지 마세요 — 다른 축입니다.

범용 기기와 전용 기기를 함께 대상으로 하는 앱은 기기를 판별해(모델명 등 — 기준은 앱이 정합니다) 전용 기기에서만 부르세요. 같은 모델에 카메라 배치가 여럿이라 모델로 장착이 갈리지 않는 기기는 `.faceProbe` 를 쓰세요.

```swift
// 범용 앱이 전용 키오스크에서도 돈다 — 기기를 판별하는 기준(isOurKiosk)은 앱이 정합니다.
if isOurKiosk() {
    // 처음 한 번은 .faceProbe 로 돌려 effectiveOrientation.cameraMounting 을 얻고, 그 값을 하드코딩합니다.
    // 화면 방향은 넘기지 않습니다(신고 값) — 얻은 장착이 그 화면 방향을 기준으로 한 값입니다.
    session.overrideOrientationPolicy(.fixed(mounting: VultusCameraMounting(degrees: 270)))
}
```

세션을 연 직후, 측정을 시작하기 전에 고르세요. 시작을 기다리는 동안부터 남은 프레임을 다 처리할 때까지는 거절하고(`.notAllowedWhileMeasuring`), 바꾸면 방향을 처음부터 다시 정합니다 — 그동안 `effectiveOrientation` 은 `nil` 입니다(측정이 끝난 뒤 · 전송 전 훅 동안 고른 것은 측정 정리 때 반영됩니다).

**측정 중에는 방향이 바뀌지 않습니다.** 측정이 끝날 때까지 방향을 얼리므로 측정 중에 기기 · 화면을 돌려도 분석 방향은 그대로입니다. 기본 · 고정은 시작이 방향을 기다리지 않습니다 — 아직 정하지 못했으면(첫 프레임 전) 측정의 첫 프레임에서 정하고, 그때는 `effectiveOrientation` 이 측정 중에 한 번 값을 얻지만 측정의 좌표계는 처음부터 하나입니다.

분석이 화면과 다르게 섰으면(얼굴로 맞췄거나 화면 방향을 못 박았을 때) 분석 프레임과 프리뷰의 방향이 달라지는데, 위 변환은 그 차이를 이미 반영합니다. 변환을 직접 만든다면 `effectiveOrientation` 의 `overlayRotationDegrees` 를 넘기세요(정해진 방향만 냅니다 — 정하기 전 · 다시 정하는 동안은 `nil`).

```swift
// orientation: session.effectiveOrientation 의 마지막 값
let transform = VultusPreviewTransform(imageSize: imageSize, viewSize: viewSize, fill: .fill,
                                       mirrored: true, rotationDegrees: orientation?.overlayRotationDegrees ?? 0)
```

Custom 길에서 `VultusPreviewView` 를 쓴다면 세션의 방향을 뷰에 넘겨야 변환이 맞습니다(Default 길은 SDK 가 넘깁니다).

```swift
session.effectiveOrientation
    .receive(on: DispatchQueue.main)
    .sink { preview.setEffectiveOrientation($0) }
    .store(in: &cancellables)
```

> [!IMPORTANT]
> **방향은 측정 동안만 고정됩니다.** 측정 밖에서는 기본 방식이 화면 회전을 따르므로 UI 가 돌면 다음 프레임부터 새 방향입니다 — 세션을 다시 열 필요가 없습니다. 방향이 정해지기 전(첫 프레임 전, 얼굴 기준이면 맞추기 전)에는 `detectedFace` 가 `nil` 입니다.

> [!CAUTION]
> 오버레이를 다른 뷰에 그린다면 **그 뷰의 크기가 프리뷰 뷰와 같아야 합니다.** 다르면 배율과 오프셋이 갈려 조용히 어긋납니다.

### 7.3 얼굴 가이드

얼굴을 보일 자리는 가이드 하나로 정합니다 — Default 길은 `session.setFaceGuide`, Custom 길은 `preview.faceGuide` 입니다([4.5](#45-자동-맞춤--사용자는-편한-자리에-카메라가-맞춥니다)). 자동 맞춤은 그리기와 상관없이 이 자리에 얼굴을 얹습니다.

가이드를 SDK 가 그릴지는 앱이 정합니다. 직접 그리려면 끄고, 뷰 좌표의 가이드 사각형을 읽어 쓰세요.

```swift
preview.guideOverlayEnabled = false
let rect = preview.faceGuideRect   // 뷰 좌표 — 변환 없이 그대로 그립니다
```

### 7.4 맞춤 crosshair

자동 맞춤이 도는 동안(측정 전) 얼굴이 **렌즈 중심**에서 벗어나면 표시 둘을 띄울 수 있습니다 — 얼굴을 옮길 **목적지점**(렌즈 중심, 분석 프레임의 가운데)과 **현재 지점**(얼굴 중심)입니다. 렌즈 중심 가까이에서는 숨고, 프리뷰가 얼굴을 따라가는 한계에 가까워질 만큼 벗어났을 때만 보입니다(경계에서 깜빡이지 않게 사라지는 데는 여유가 있습니다). 프리뷰가 얼굴을 따라 옮겨지면 두 표시도 함께 옮겨집니다. 측정이 시작돼 맞춤이 멈추면(대화형 시작을 누른 순간 · 비대화형 카운트다운이 끝난 순간) 숨고, 얼굴이 없거나 `guideOverlayEnabled` 가 꺼져 있어도 숨습니다.

```swift
preview.showsFramingCrosshair = true                    // 기본은 끔
preview.framingTargetCrosshairView = myTargetView       // 목적지점(렌즈 중심) 모양 — nil 이면 기본 +
preview.framingCurrentCrosshairView = myCurrentView     // 현재 지점(얼굴 중심) 모양 — nil 이면 기본 ×
// SwiftUI 모양: UIHostingController(rootView: MyCrosshair()).view — bounds 로 크기를 주고 배경은 .clear
```

**모양은 앱이 정합니다.** SDK 는 넘긴 뷰의 중심을 그 점에 맞추고 보이거나 숨기기만 합니다. 크기는 넘긴 뷰의 `bounds` 를 따릅니다(0 이면 `intrinsicContentSize`). 넘긴 뷰는 프리뷰 뷰의 하위 뷰로 옮겨 붙으며, 터치는 받지 않습니다.

---

## 8. 얼굴 검출 (Face Detection)

얼굴 검출은 **Vision**(Apple 시스템 프레임워크)으로 SDK 안에서 처리됩니다. 앱이 설정하거나 교체할 것은 없습니다 — 프레임만 넘기면 됩니다([4.3](#43-custom-길--vultuscustomsession)). 시스템 프레임워크만 쓰므로 SDK 는 검출기 관련 의존성을 하나도 더하지 않습니다.

검출 결과는 `session.detectedFace` 로 관찰합니다([6절](#6-상태-구독)).

### 왜 교체할 수 없나

**검출기의 규격(얼굴 박스 · 랜드마크)이 측정 품질의 전제이기 때문입니다.** SDK 는 그 규격을 보장하는 검출기만 씁니다.

검출기를 갈아끼우면 SDK 가 이 규격을 보장할 수 없고, **어긋나도 예외가 나지 않습니다** — 조용히 BPM 이 흔들리고 표정 분포가 밀릴 뿐입니다.

### 검출 결과 — 맞춘 값과 원본

| 필드 | 뜻 |
| :--- | :--- |
| `boundingBox` · `landmarks`(8 점) · `imageWidth` · `imageHeight` | SDK 가 측정 규격으로 맞춘 값 — 회전 보정된 분석 프레임의 픽셀 좌표(원점 왼쪽 위, 미러 없음). 상자는 프레임 안으로 자른 값입니다. **두 플랫폼이 같은 규격입니다** |
| `headEulerAngleX/Y/Z` | 머리 각(도) — Vision 의 값을 도로 옮긴 것 |
| `faceObservation` | Vision 의 검출 결과 원본(`VNFaceObservation`) — 랜드마크 영역 · 머리 각 등 |

**`faceObservation` 은 일부러 열어 둔 통로입니다.** 얼굴 검출은 비싼 연산이라, SDK 가 쓰고 버리면 다른 용도가 필요한 앱이 같은 프레임에 검출을 다시 돌려야 합니다. 원본을 그대로 넘기고, SDK 는 측정에 쓸 값만 따로 쥡니다 — 넘긴 뒤 SDK 는 이 관측을 읽지 않으므로 앱이 어떻게 다뤄도 측정은 영향받지 않습니다. Vision 객체의 스레드 안전성은 문서화돼 있지 않으니 한 관측은 한 스레드에서 읽으세요.

#### 두 플랫폼의 검출 결과 비교 (Android · iOS 공통)

Android 와 iOS 는 얼굴 검출기가 다릅니다 — Android 는 ML Kit, iOS 는 Vision 입니다(둘 다 SDK 안에 고정). SDK 가 두 플랫폼에서 같은 규격으로 맞춰 주는 값은 `boundingBox` · `landmarks`(8 점) · `imageWidth` · `imageHeight` 뿐이고, 검출 결과 원본과 머리 각은 각 검출기의 값입니다. **두 플랫폼의 값을 함께 모으거나 비교하는 앱은 아래 차이를 직접 맞추세요.**

| | Android — `faceInfo`(ML Kit `Face`) | iOS — `faceObservation`(Vision `VNFaceObservation`) |
| :--- | :--- | :--- |
| 좌표 | 회전 보정된 분석 프레임의 픽셀, 원점 왼쪽 위 | 0~1 정규화, 원점 **왼쪽 아래** — 상자는 회전 보정된 분석 프레임에 대해, 랜드마크 점은 **얼굴 상자에 대해** 정규화(`pointsInImage(imageSize:)` 에 `imageWidth` · `imageHeight` 를 넘겨 프레임 좌표로 옮긴다 — 원점은 여전히 왼쪽 아래) |
| 상자 | ML Kit 의 상자 — SDK `boundingBox` 는 이것을 프레임 안으로 자른 것(얼굴이 프레임 가장자리에 걸치면 더 작다) | Vision 의 상자 — SDK `boundingBox`(측정 규격에 맞춘 상자)와 **다른 상자** |
| 랜드마크 | 점 몇 개(`detectContour` 를 켜면 윤곽선도) | 영역별 점 묶음(`VNFaceLandmarks2D`) |
| 머리 각 | `faceInfo.headEulerAngleX/Y/Z` — 도. **pitch 는 고개를 들면 양수** | `headEulerAngleX/Y/Z` — 도(원본은 라디안). **pitch 는 고개를 들면 음수** |
| 머리 각의 크기 | 같은 자세라도 두 검출기의 각도 크기가 다릅니다(축마다 다름) — 부호만 뒤집어서는 맞지 않습니다 | 〃 |
| 검출기 옵션 | `Initializer` 의 `minFaceSize` · `useAccurateMode` · `detectContour` | 없음 |

얼굴이 너무 멀거나 가깝거나 화면 밖에 걸렸는지는 상자의 크기 · 위치로 직접 판단하지 말고 SDK 의 촬영 조건(`captureCondition`)으로 보세요 — 두 플랫폼이 같은 기준으로 냅니다.

---

## 9. 라이선스 검증 및 예외 처리 (License & Error Handling)

```swift
Vultus.isInitialized       // Bool
Vultus.license.isValid     // Bool
Vultus.license.error       // String?
```

전역 접근자 전체와 초기화 전 동작은 [3.3 전역 접근자](#33-전역-접근자)에 있습니다.

`Vultus.license` 는 **마지막 검사 결과**입니다(`isValid` · `grantedFeatures` · `error`). 워밍업이 끝나기 전에는 `isValid` · `error` 가 각각 `false` · `nil` 이며, 그 뒤로는 워밍업과 각 `startMeasure()` 시점의 검사 결과를 반영합니다. 측정 결과 제출 중 서버가 세션을 거절해 SDK 가 다시 받은 결과도 반영합니다. 유효 시간 뒤의 재확인이 경로 문제(네트워크 · 프록시 · 인증서)로 실패해 지금 세션으로 측정한 경우는 오류로 남지 않습니다.

`Initializer.initialize()` 는 `InitializationError` 를 던집니다.

| 케이스 | 의미 |
| :--- | :--- |
| `alreadyInitialized` | 이미 초기화됨 |
| `devServerInReleaseBuild` | 릴리스 빌드에서 `useDevServer()` 를 불렀음 |

**SDK 가 예외를 던지는 자리는 `initialize()` 하나뿐이고, 던지는 것은 위 둘뿐입니다.** 그 밖의 실패는 상태(`prepareState` · `Vultus.license`)나 돌려주는 값(세션 열기의 `Result` · `startMeasure` 의 결말)으로 전달됩니다.

> [!WARNING]
> **`useDevServer()` 는 개발 서명 빌드에서만 허용되며, 개발 서버는 정상 동작을 보장하지 않습니다**(가용성 · 응답 형태가 예고 없이 바뀔 수 있습니다 — 출시 판단은 운영 서버로 하세요). Xcode 에서 개발 인증서로 서명해 설치한 빌드만 해당하며, **TestFlight · App Store · Ad Hoc 빌드에서는 `initialize()` 가 `devServerInReleaseBuild` 를 던집니다.** 시뮬레이터는 개발 빌드로 봅니다. 판정은 SDK 가 앱 번들의 서명 정보를 직접 읽어서 하며, 그 경로를 피해 가도 SDK 는 개발 서버에 접속하지 않습니다.
>
> 디버그 구성에서만 켜려면 컴파일 조건으로 가르세요.
>
> ```swift
> var initializer = Vultus.Initializer(licenseCode: …, holderKey: …, clientKey: …)
> #if DEBUG
> initializer = initializer.useDevServer()
> #endif
> try initializer.initialize()
> ```

네이티브 객체 생성 실패는 예외가 아니라 `prepareState == .failed` 로 나타납니다 — 생성이 백그라운드에서 진행되고 `initialize()` 는 즉시 반환하기 때문입니다.

> [!CAUTION]
> **초기화 실패는 앱이 반드시 다뤄야 하는 지점입니다.**
>
> 초기화에 실패하면 SDK 는 아무것도 하지 않습니다. 그 상태에서 `Vultus.current` 에 접근하면 **초기화되지 않았다는 사유와 함께 앱이 멈춥니다.** SDK 가 대신 판단해 줄 수 있는 것이 없습니다 — 측정 화면을 띄울지, 재시도할지, 안내하고 종료할지는 앱의 결정입니다.
>
> **`catch` 에서 로그만 남기고 넘어가면 안 됩니다.** `ContentView` 의 `@ObservedObject private var vultus = Vultus.current` 처럼 뷰가 만들어지는 순간 접근이 일어나므로, 곧바로 그 자리에서 죽습니다. **화면을 그리기 전에 갈라야 합니다.**
>
> ```swift
> @main
> struct MyApp: App {
>     private let initializationError: Error?
>
>     init() {
>         do {
>             try Vultus.Initializer(licenseCode: …, holderKey: …, clientKey: …).initialize()
>             initializationError = nil
>         } catch {
>             initializationError = error
>         }
>     }
>
>     var body: some Scene {
>         WindowGroup {
>             if let initializationError {
>                 ErrorView(error: initializationError)   // 실패 안내
>             } else {
>                 ContentView()                          // 정상 경로
>             }
>         }
>     }
> }
> ```
>
> `Vultus.isInitialized` 로도 확인할 수 있습니다. 샘플앱(`Sample/VultusSample/VultusSampleApp.swift`)이 이 형태로 되어 있습니다.

> [!IMPORTANT]
> **라이선스 검증은 앱 식별자를 함께 확인합니다**(코어의 `PKG_NAME_MISMATCH` + 서버 검증). 서버에 등록되지 않은 번들 ID 로 실행하면 검증이 실패합니다. 등록된 값으로 바꾸거나 서버에 추가하세요.

### 9.1 검사 시점과 복구

라이선스는 한 번만 검사하지 않습니다. 검사가 실패한 채로 굳으면 코어가 입구에서 모든 처리를 반환해 **BPM·신호·FER 이 전부 나오지 않으면서도 예외는 발생하지 않는** 상태가 되기 때문입니다.

| 시점 | 재시도 | 실패했을 때 |
| :--- | :--- | :--- |
| 워밍업 (`initialize()` 직후, 백그라운드) | 백오프 3회 | `prepareState` 가 `.licenseInvalid` |
| `startMeasure()` 진입 | 1회(워밍업 중이면 워밍업이 끝나기를 기다린 뒤) | `startMeasure()` 가 `.refused(.licenseInvalid)` |
| 유효 시간(서버가 정한다, 기본 3 시간)이 지난 뒤의 `startMeasure()` | 1회 — 다시 확인한다 | 서버가 명시적으로 거절하면 `.refused(.licenseInvalid)`, 그 밖의 실패(네트워크 · 프록시 · 인증서)는 지금 세션으로 측정하고 다음 시작에서 다시 확인합니다 |
| 측정 결과 제출을 서버가 세션 문제로 거절(HTTP 401) | 라이선스를 다시 받아 한 번 다시 보냄 | 다시 받지 못했거나 또 거절되면 결말은 `.finished` 이고 응답의 `error_code` 가 `API_HTTP_ERROR`([9.3](#93-오류-응답-json)) |

재시도 대상은 **시간이 지나면 풀릴 수 있는 실패**뿐입니다 — 연결 실패·타임아웃·서버 5xx·408·429. 서버가 라이선스를 거절했거나(4xx) 번들 ID 가 어긋난 경우(`PKG_NAME_MISMATCH`), 서버 인증서를 믿을 수 없는 경우(`TLS_UNTRUSTED`, [9.4](#94-서버-인증서-검증))는 다시 물어도 답이 같으므로 재시도하지 않습니다.

라이선스 오류는 `prepareState` 를 `.failed` 로 만들지 않습니다. `.licenseInvalid` 로 알리되 측정은 막지 않습니다([3.2](#32-워밍업vultuspreparestate)).

### 9.2 라이선스 기능 플래그 (Feature Flags)

라이선스마다 **허용된 기능이 다릅니다.** 요청한 기능이 허용되지 않으면 그 기능만 동작하지 않고, 측정 자체는 계속되며 예외도 발생하지 않습니다.

```swift
let granted: Set<String> = Vultus.license.grantedFeatures

if Vultus.current.configuration.enableFER && !granted.contains("fer") {
    // 표정 UI 를 숨기거나 안내 문구를 띄운다
}
```

초기화 전이거나 라이선스 검증 전·실패 후에는 **빈 집합**입니다.

| 토큰 | 기능 | 결과에서 받는 자리 |
| :--- | :--- | :--- |
| `fer` | 표정 인식(FER) | 측정 중 `emotion` · `VultusAnalysisResult.Entry``.fer` |
| `env` | 측정 환경 — 조도 · 화면 밝기 · 프레임당 카메라 상태 | `VultusAnalysisResult.Entry``.env` · `.camera` |
| `chroma` | 크로마 신호 | `VultusAnalysisResult.Entry``.chroma` |
| `rawppg` | 원신호 | `VultusAnalysisResult.Entry``.ppgRawJson`(JSON 문자열) |
| `rawface` | 얼굴 검출 결과 | `VultusAnalysisResult.Entry``.faceJson`(JSON 문자열) |
| `imu` | 측정 구간의 가속도 · 자이로 스트림 | `VultusAnalysisResult.imuJson`(JSON 문자열) |
| `hrv_das` | 스트레스·우울·불안 지표 | (준비 중) |

`rawppg` · `rawface` · `imu` 의 JSON 문자열 안 필드는 해당 기능을 받은 라이선스와 함께 제공하는 문서를 따릅니다. 세 JSON 문자열은 응답 원문을 그대로 잘라 담은 것입니다 — 파서가 풀었다가 다시 만들지 않으므로 이름 순서 · 숫자 표기가 응답과 같고, 필요한 앱만 풀면 됩니다.

`chroma` · `rawppg` · `rawface` 중 하나라도 있으면 빠진 프레임도 함께 받습니다 — `VultusAnalysisResult.Entry.gap`(`VultusAnalysisResult.Gap` — `frames` · `skipped` · `reasons`: `VultusAnalysisResult.Gap.Reasons` 옵션 집합 `.noFace` 등). 그 엔트리가 간극의 끝이고 시작은 직전 엔트리이며, 빠진 것이 없으면 `nil` 입니다.

#### FER 이 허용되지 않으면

`enableFER(true)` 로 요청했더라도 라이선스가 `fer` 를 주지 않으면:

* **추론 모델을 로드하지 않습니다.** 메모리와 초기화 비용이 들지 않습니다.
* `emotion` 은 **계속 값을 내지만 비어 있습니다** — `emotionIndex = -1`, `label` 은 `"Unknown"`. 흐름을 아예 멈추지 않는 이유는, 멈추면 앱이 "카메라가 얼굴을 못 잡나"를 먼저 의심하게 되고 그쪽을 아무리 고쳐도 달라지지 않기 때문입니다.
* 측정 시작 시 SDK 로그(subsystem `io.haii.vultus`, category `session`)에 오류로 사유가 **한 번** 기록됩니다.

`emotionIndex` 가 음수인 경우를 값 없음으로 처리하면 별도 분기 없이 안전합니다.

```swift
let label = result.emotionIndex >= 0 ? result.label : "--"
```

#### ⚠️ 권한 변경은 늦게 반영될 수 있습니다

라이선스 세션은 **유효 시간(서버가 정한다, 기본 3 시간) 동안 유지**됩니다. 그동안 측정은 라이선스 확인에 네트워크를 타지 않으므로(그래서 측정 시작이 빠릅니다), **앱이 실행 중일 때 서버에서 권한을 바꿔도 곧바로 반영되지는 않습니다.**

* 서버 응답에 실리는 데이터(`env` · `chroma` · `rawppg` · `rawface` · `imu` · `hrv_das`)는 매 측정 제출마다 서버가 다시 확인하므로 즉시 반영됩니다.
* **클라이언트에서 동작하는 기능(FER)** 은 SDK 가 라이선스를 다시 확인한 뒤의 측정부터 반영됩니다 — 유효 시간이 지난 뒤의 `startMeasure()`, 또는 제출 중 서버가 세션을 거절했을 때(권한이 바뀐 경우 포함) 다시 확인합니다. 새로 주어진 권한은 그때부터 동작하고, 거둔 권한은 그때부터 FER 결과가 비어 옵니다(`emotionIndex = -1`).
* 구매 직후 곧바로 쓰게 하려면 `Vultus.license.grantedFeatures` 로 현재 권한을 확인해 "앱을 다시 시작해 주세요"를 띄우는 것이 확실합니다.

### 9.3 오류 응답 JSON

결말 `.finished(responseJSON:)` 의 응답에 오류가 담기면 다음 형태입니다.

```json
{
  "status": "error",
  "error_code": "API_HTTP_ERROR",
  "message": "Measurement API failed with HTTP 401"
}
```

측정 결과 제출은 **SDK 가 다시 보내지 않습니다** — 서버가 세션을 다시 요구한(HTTP 401) 때만 라이선스를 다시 받아 한 번 더 보냅니다. 오류로 끝나면 측정 데이터는 남지 않으므로 다시 측정하도록 안내하세요.

| `error_code` | 뜻 |
|---|---|
| `API_NETWORK_ERROR` | 서버에 닿지 못했거나 응답을 받지 못했습니다(네트워크 끊김 · 시간 초과) |
| `API_HTTP_ERROR` | 서버가 오류 상태(HTTP 4xx · 5xx)로 답했습니다. 401 이면 마지막 라이선스 확인 뒤 서버에서 라이선스(권한 등)가 바뀌어 세션이 무효해졌고, SDK 가 라이선스를 다시 받지 못했거나 다시 보냈는데도 거절된 경우입니다 |
| `API_TLS_UNTRUSTED` | 서버 인증서를 믿을 수 없습니다(아래 「서버 인증서 검증」) |
| `API_SIGNATURE_VERIFY_FAILED` | 응답의 서명을 확인하지 못했습니다(아래) |
| `HTTP_INIT_FAILED` | 기기에서 통신을 준비하지 못했습니다 |
| `SUBMISSION_BUILD_FAILED` | 기기에서 측정 데이터를 보낼 형태로 만들지 못했습니다(보내지 않았습니다) |
| 라이선스 검사의 코드(`LICENSE_*` · `PKG_NAME_MISMATCH` · `NETWORK_ERROR` · `TLS_UNTRUSTED` 등) | 보내기 전에 라이선스가 유효하지 않아 보내지 않았습니다 |

측정 결과 제출에서 서버 인증서를 믿을 수 없으면 `error_code` 가 `API_TLS_UNTRUSTED` 입니다([9.4](#94-서버-인증서-검증)).

측정 결과는 서버가 서명해 보내고 SDK 가 확인한 뒤에만 넘깁니다. 확인에 실패하면 `error_code` 가 `API_SIGNATURE_VERIFY_FAILED` 입니다 — 통신 중간에서 응답이 바뀌었다는 뜻이므로 결과로 쓰지 말고, 네트워크(프록시 · VPN · 보안 앱)를 확인한 뒤 다시 측정하도록 안내하세요.

### 9.4 서버 인증서 검증

SDK 는 Vultus 서버와 통신할 때 서버 인증서를 **iOS 의 신뢰 저장소**로 검증합니다. 앱이 별도로 지정하는 인증서는 SDK 통신에 쓰이지 않습니다.

> [!NOTE]
> **iOS 의 신뢰 저장소에는 사용자가 설치하고 「전체 신뢰」 를 켠 루트 인증서도 들어갑니다.** 그런 기기에서는 SDK 통신을 가로챌 수 있습니다 — Android 판은 시스템 인증 기관만 믿어 거절하므로 두 플랫폼이 다릅니다. 측정 데이터는 TLS 안에서 한 번 더 암호화되고 측정 결과는 서버 서명으로 확인하므로, 가로채더라도 측정 내용을 읽거나 결과를 바꿀 수는 없습니다.

검증에 실패하면 라이선스 검사는 `TLS_UNTRUSTED`, 측정 결과 제출은 `API_TLS_UNTRUSTED` 로 끝나며 재시도하지 않습니다. 공용 Wi-Fi 의 로그인 페이지나 통신을 가로채는 프록시를 거치는 네트워크에서 주로 일어납니다.

오류 메시지 끝에 원인이 붙습니다. 원인별 대응은 다음과 같습니다.

| 메시지의 원인 | 뜻 | 대응 |
|---|---|---|
| `not issued by an authority the system trusts` | 인증서가 시스템이 믿는 인증 기관으로 이어지지 않습니다 | 프록시 · VPN · 보안 앱 · 네트워크 로그인 페이지를 거치는지 확인하고, 다른 네트워크에서 다시 시도하도록 안내합니다 |
| `expired or not yet valid` | 인증서의 유효 기간 밖입니다 | 기기의 날짜 · 시간 설정(자동 설정)을 확인하도록 안내합니다 |
| `does not match the server name` | 다른 서버의 인증서가 왔습니다 | 네트워크가 연결을 다른 곳으로 돌리는 경우입니다(로그인 페이지 등). 네트워크 로그인을 마치거나 다른 네트워크를 쓰도록 안내합니다 |
| `was rejected` | 그 밖의 이유로 인증서를 받아들이지 않았습니다 | 다른 네트워크에서도 반복되면 문의해 주세요 |

인증서를 확인하는 과정 자체가 이 기기에서 실패한 경우(인증서 탓이 아닌 일시적 오류)는 인증서 오류가 아니라 `NETWORK_ERROR` · `API_NETWORK_ERROR` 로 옵니다 — 라이선스 검사의 `NETWORK_ERROR` 는 다른 네트워크 오류처럼 다시 시도되고, 측정 결과 제출의 `API_NETWORK_ERROR` 는 다시 보내지 않으므로 다시 측정합니다.

---

## 10. 샘플 앱 구동 방법 (Sample App Guide)

1. **Xcode 에서 `Sample/VultusSample.xcodeproj` 를 연다**
2. **iOS 플랫폼 컴포넌트를 설치한다** — Xcode → Settings → Components

   Xcode 버전이 요구하는 iOS 플랫폼이 없으면 iOS destination 이 **아예 잡히지 않습니다.** 시뮬레이터 런타임만으로는 부족합니다.
3. `VultusSample/VultusSampleApp.swift` 의 `Secrets` 에 발급받은 `licenseCode` · `holderKey` · `clientKey` 를 넣는다
4. `VultusSample` 타깃 → Signing & Capabilities 에서 Team 선택
5. 실기기를 연결하고 ⌘R

샘플은 저장소 루트의 패키지를 **상대 경로로** 참조합니다. 저장소 구조를 그대로 두세요 — `Sample/` 을 다른 곳으로 옮기면 패키지를 찾지 못합니다.

샘플의 번들 ID 는 `com.example.vultus` 입니다. 라이선스는 앱 식별자를 함께 확인하므로 이 식별자가 등록된 라이선스 값을 넣어야 하고, 번들 ID 를 바꾸면 검증이 실패합니다([9절](#9-라이선스-검증-및-예외-처리-license--error-handling)).

커맨드라인에서 빌드·설치하려면:

```shell
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -project Sample/VultusSample.xcodeproj -scheme VultusSample \
  -destination 'platform=iOS,id=<UDID>' -configuration Debug build

xcrun devicectl device install app --device <이름> <경로>/VultusSample.app
xcrun devicectl device process launch --device <이름> com.example.vultus
```

`xcode-select` 가 Command Line Tools 를 가리키면 `devicectl` 을 찾지 못하므로 `DEVELOPER_DIR` 지정이 필요합니다.

---

## 11. 모범 사례 및 트러블슈팅

### 11.1 측정 품질

- **자세가 중요합니다.** 기기를 아래에서 위로 든 자세는 측정을 크게 흔들고, 눈높이 정면에서 가장 안정됩니다 — 사용자를 눈높이 정면으로 유도하세요.
- **`lockCameraOnStartMeasure` 를 켜세요.** AE/AWB · 초점이 흔들리면 신호가 함께 흔들립니다. 락을 걸 카메라는 SDK 가 프레임의 연결에서 얻으므로 앱이 등록할 것은 없습니다.
- **조명이 한쪽으로 치우치지 않게 하세요.** 얼굴 한쪽에 그늘이 지면 신호가 약해집니다. 정면광이나 고른 확산광이 가장 좋습니다.
- **분석 길이는 `startMeasure(analysisWindow:)` 로 넘깁니다.** 창을 채우면 **SDK 가 스스로 멈춥니다** — 앱이 타이머를 들 필요가 없습니다. 더 모으려면 `extraSeconds` 를, 앱이 직접 멈추려면 `extraSeconds: nil` 을 넘깁니다(어느 쪽이든 하드 안전 종료 — 기본 180 초 — 에서 SDK 가 멈춥니다). 길이는 **유효 신호가 모인 시간**으로 세므로 벽시계보다 오래 걸릴 수 있습니다 — 남은 시간은 `progress` 로 보여 주세요.
- **얼굴 크기가 곧 신호 품질입니다.** 얼굴이 작을수록 신호에 쓰이는 화소가 줄고, 일정 크기 아래에서는 화질 손실이 더해집니다. 크기는 **자동 맞춤이 맞춥니다**(§4.5) — 앱은 맞춤 상태(`.limited`)가 요청할 때만 사용자에게 다가오거나 물러나라고 안내하면 됩니다.

  위쪽에도 한계가 있습니다. **얼굴이 너무 크면** 고개를 조금만 돌려도 얼굴이 프레임을 벗어나 **그 구간을 측정에 쓰지 못합니다** — 촬영 조건의 `.tooClose` 를 따르세요. 샘플앱은 SDK 의 촬영 조건을 따라 쓸 만하면 초록, 작으면 노랑, 너무 가깝거나 화면 밖에 걸리면 주황으로 표시합니다 — 두 색만 쓰면 이미 너무 가까운 사용자가 "더 가까이"로 읽고 상황을 악화시킵니다.

  그렇다고 사용자가 불편을 느끼는 거리까지 당기게 하면 자세가 무너져 손해가 더 큽니다.

### 11.2 자주 겪는 문제

| 증상 | 원인 |
| :--- | :--- |
| SPM resolve 가 버전을 못 찾음 | 프리릴리스 버전에 `from:` 사용 → `exact:` 로 지정 ([2.1](#21-swift-package-추가)) |
| SPM 이 프레임워크 다운로드 실패 | 릴리스 자산 호스트가 사내 프록시·방화벽에 막힘 ([2.1](#21-swift-package-추가)) |
| 샘플이 패키지를 못 찾음 | `Sample/` 을 원래 위치에서 옮김 → [10절](#10-샘플-앱-구동-방법-sample-app-guide) |
| iOS destination 이 안 보임 | Xcode 에 iOS 플랫폼 컴포넌트 미설치 |
| Intel Mac 에서 시뮬레이터 빌드 실패 | x86_64 슬라이스 미제공 (Apple Silicon 전용) |
| 얼굴 박스가 좌우 반대로 움직임 | 프리뷰 뷰가 주는 변환을 쓰지 않음 → [7절](#7-프리뷰와-오버레이) |
| 라이선스 실패 | 번들 ID 미등록 → [9절](#9-라이선스-검증-및-예외-처리-license--error-handling) |
| 프레임 변환이 깨짐 | 픽셀 포맷이 2-plane full-range YUV 가 아님 → [4.3](#43-custom-길--vultuscustomsession) |

### 11.3 프레임 흐름 진단 (`[FRAME_STATS]`)

rPPG 는 **균일한 프레임 간격을 전제**합니다. BPM 이 튀거나 선명도(`signalClarity`)가 낮게 나오는데 조명·자세에 문제가 없다면, 프레임이 제대로 흘렀는지부터 확인하세요.

측정이 끝날 때마다 한 줄이 남고, 같은 값이 측정 데이터와 함께 서버로도 전송됩니다.

```
[FRAME_STATS] enqueued=621 outOfOrder=0 maxGapMs=0
```

| 로그 키 | 읽는 법 |
| :--- | :--- |
| `enqueued` | 측정 동안 실제로 처리된 프레임 수. **측정 시간 × 30 에 크게 못 미치면 프레임이 버려지고 있다는 뜻**입니다 |
| `outOfOrder` | 신호 처리에 들어간 순서가 뒤집힌 횟수 |
| `maxGapMs` | 가장 크게 뒤집힌 폭(ms) |

**`outOfOrder` 는 보통 0 입니다.** 얼굴 검출이 프레임 간격보다 한참 오래 걸리면(저사양 기기 · 발열) 일부 프레임의 처리 순서가 바뀔 수 있습니다.

서버로 보내는 데이터는 영향을 받지 않습니다. 영향을 받는 것은 **실시간 표시용 BPM 과 신호 그래프**뿐입니다.

`maxGapMs` 로 심각도를 판단하세요.

- **0** — 정상입니다
- **0 이 아니면** — 검출이 프레임 간격을 크게 넘은 구간이 있었다는 뜻입니다. 저사양 기기 · 발열인 경우이며, 폭이 클수록 실시간 BPM 이 눈에 띄게 튈 수 있습니다

### 11.4 측정 품질 진단

BPM 이 튀거나 표정이 이상할 때, **먼저 확인할 것은 거리와 자세**입니다. 배포 패키지는 프레임 단위 진단 로그를 남기지 않으므로(앱을 `Debug` 로 빌드해도 같습니다), 같은 확인은 공개 흐름으로 합니다.

1. **머리 각도(pitch)** — 촬영 조건(`captureCondition`)의 원인 `.headTilted` · `.headTurned` 가 뜨지 않는 자세를 기준으로 삼으세요(각도 값은 `detectedFace` 의 `headEulerAngleX` — Android 와 부호 · 크기가 달라 플랫폼마다 같은 숫자로 판단할 수 없습니다, [8절](#8-얼굴-검출-face-detection)). rPPG 품질에 크게 영향을 줍니다 — 기기를 아래에서 올려 든 자세는 BPM 을 크게 흩뜨립니다. 기기를 눈높이로 들어 정면을 보게 하세요
2. **얼굴 크기(거리)** — 촬영 조건(`captureCondition`)의 원인 `.tooFar` · `.tooClose` 로 판단하세요. 너무 작으면 신호가 약하고, 너무 크면 고개를 돌릴 때 얼굴이 프레임을 벗어납니다. `detectedFace` 의 `boundingBox` 크기는 참고값입니다 — 얼굴이 프레임 가장자리에 걸치면 잘려 작아집니다
3. **화면용 심박수의 상태** — `displayBpm` 의 `state`. 워밍업인 동안은 아직 값이 나오기 전이고, 추정 중은 값이 흔들리는 구간입니다. 표시 전용 값이므로 측정 결과로 모으지 마세요([6](#6-상태-구독))
4. **빠진 프레임** — 측정 결과의 `VultusAnalysisResult.Entry.gap`(`VultusAnalysisResult.Gap.reasons`)이 얼굴을 놓친 구간과 사유를 알려 줍니다(해당 라이선스 기능이 있을 때)

프레임 간격 자체가 의심되면 [11.3](#113-프레임-흐름-진단-frame_stats) 을 보세요.

### 11.5 알려진 제약

- **표정 결과는 시선에 크게 좌우됩니다.** 결과를 모아 평균 내도 보정되지 않으므로, 표정 결과를 쓰신다면 **사용자가 렌즈를 보도록 유도**하세요.
- **CoreML 미적용.** ONNX Runtime 이 CPU 프로바이더로 동작합니다.
- **외장(UVC) 카메라 제어는 Android 전용입니다.** iOS 에는 외장 카메라 어댑터 · 상태 API 가 없습니다.
- **촬영 중에 기기를 가로 ↔ 세로로 돌리면 얼굴 상자가 어긋날 수 있습니다.** 방향은 측정 동안 고정되어, 측정 중에 돌린 뒤의 영상은 얼굴이 누운 채 분석됩니다. 얼굴 상자가 얼굴에서 밀리고 분석 품질이 떨어질 수 있습니다. 측정 중에 기기를 돌렸다면 그 측정을 취소하고 다시 시작하세요 — 측정 밖에서는 기본 방식이 화면 회전을 따라 다시 맞춥니다. UI 를 한 방향으로 고정한 앱은 기기를 돌려도 화면 회전이 바뀌지 않으므로 얼굴이 누운 채로 남습니다(§7.2 의 방향 안내).
- **검출이 크게 밀리면 실시간 BPM 과 그래프가 잠시 흔들릴 수 있습니다.** 저사양 기기나 발열로 얼굴 검출이 프레임 간격보다 한참 오래 걸리면 일부 프레임의 처리 순서가 바뀔 수 있습니다(`[FRAME_STATS]` 의 `outOfOrder` 가 0 이 아닌 측정). 화면의 표시용 BPM · 신호 그래프만 잠시 흔들리고, 서버로 보내는 결과는 영향을 받지 않습니다.

---

## 12. 앱 스토어 제출 — 수출 규정 신고

App Store 에 올리는 모든 앱은 **수출 규정(Export Compliance) 질문에 답해야** 합니다.
Vultus SDK 는 암호화를 사용하므로, SDK 를 넣은 앱은 "암호화를 사용하지 않음" 으로
답할 수 없습니다. 답을 고르려면 무엇이 쓰이는지 알아야 하므로 아래에 밝힙니다.

### 12.1 SDK 가 사용하는 암호화

| 무엇 | 알고리즘 | 쓰이는 곳 |
| :--- | :--- | :--- |
| 전송 채널 보호 | TLS | 라이선스 검증 · 측정 결과 전송 |
| 전송 데이터 암호화 | **X25519 ECDH + AES-256-GCM** | 측정 페이로드와 메타데이터 |
| 라이선스 응답 · 측정 결과 응답 · 서버 조정값 검증 | **Ed25519 서명 검증** | 세션 수립 · 결과 수신 |

- **암호화 구현은 SDK 안에 정적으로 포함**됩니다(OpenSSL). iOS 가 제공하는 암호화
  프레임워크를 호출하는 방식이 **아닙니다.**
- 알고리즘은 모두 공개된 국제 표준이며 독자 방식은 없습니다.
- 측정 데이터는 **TLS 위에 한 번 더 암호화**되어 전송됩니다.

### 12.2 답하는 방법

두 가지가 있고, 앱이 하나를 고릅니다.

**① App Store Connect 에서 답한다** — 아무 설정도 하지 않으면 업로드한 빌드가
`Missing Compliance` 상태로 멈추고, 질문에 답해야 TestFlight 테스터와 심사로
넘어갑니다.

**② `Info.plist` 에 미리 넣는다** — 업로드마다 묻지 않습니다.

```
ITSAppUsesNonExemptEncryption = NO    // 면제 대상만 사용
ITSAppUsesNonExemptEncryption = YES   // 면제 대상 아님
```

`YES` 인 경우 `ITSEncryptionExportComplianceCode` 도 함께 넣어야 하며, 그 코드는
규정 신고 절차를 거쳐 발급받습니다.

Xcode 가 `Info.plist` 를 생성하는 프로젝트(`GENERATE_INFOPLIST_FILE = YES`)라면
빌드 설정에 넣습니다.

```
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO
```

### 12.3 ⚠️ 판단할 때 주의할 것

**"표준 공개 알고리즘을 쓴다" 는 면제 사유가 아닙니다.** 규제 대상이 되는 것이 오히려
AES-256 같은 표준 강암호이며, 독자 알고리즘 여부는 추가 질문으로 갈지를 가르는 기준일
뿐입니다.

면제 여부는 **알고리즘이 아니라 용도**로 정해집니다. 예를 들어 인증·전자서명에만
쓰거나, 운영체제가 제공하는 암호화만 호출하는 경우가 면제 항목에 해당합니다.
**Vultus SDK 는 사용자 측정 데이터 자체를 암호화하고 암호화 구현을 직접 포함**하므로,
그 두 항목으로는 설명되지 않습니다.

어떤 면제 항목에 해당하는지, 해당하지 않아 신고가 필요한지는 **앱마다 다르며 제출자가
판단할 사항**입니다. 이 문서는 판단에 필요한 사실만 제공합니다.
