import SwiftUI
import Vultus

/// 워밍업 상태에 따라 화면을 나누고, 준비되면 **두 길 중 하나를 고른다**.
///
/// - `DefaultMeasureView` — SDK 가 카메라를 쥔다. 앱은 프리뷰 뷰를 놓기만 한다(`VultusDefaultSession`).
/// - `CustomMeasureView` — 앱이 카메라를 쥐고 SDK 세션에 프레임을 넘긴다(`VultusCustomSession`).
struct ContentView: View {
    @ObservedObject private var vultus = Vultus.current

    var body: some View {
        Group {
            switch vultus.prepareState {
            case .ready:
                WayChooser(licenseError: nil)
            case .licenseInvalid:
                // **측정 화면을 막지 않는다.** 대부분 일시적 네트워크 단절이고,
                // startMeasure 가 진입할 때 다시 검사해 통과하면 ready 로 돌아간다.
                WayChooser(licenseError: Vultus.license.error ?? "사유 불명")
            case .preparing:
                PreparingView(message: "측정 준비 중입니다...", showProgress: true)
            case .failed:
                PreparingView(message: "초기화에 실패했습니다.\n앱을 다시 실행해 주세요.",
                              showProgress: false)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// 두 길을 고른다. 각 길이 무엇을 쥐는지 한 줄로 붙인다 — SDK 사용자가 자기 앱에 맞는 쪽을 고르게.
private struct WayChooser: View {
    let licenseError: String?
    /// 켜면 측정 화면이 열리자마자 버튼 없이 시작한다(비대화형). 끄면 버튼을 눌러 시작한다(대화형).
    @State private var autoStart = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Vultus Sample").font(.title2.bold())
                Text("SDK \(Vultus.sdkVersion)").font(.caption).foregroundStyle(.secondary)

                NavigationLink {
                    DefaultMeasureView(autoStart: autoStart).navigationBarTitleDisplayMode(.inline).navigationTitle("Default")
                } label: {
                    wayLabel("Default", detail: "SDK 가 카메라 · 프리뷰 · 줌을 쥔다. 앱은 프리뷰 뷰를 놓기만 한다.")
                }
                NavigationLink {
                    CustomMeasureView(autoStart: autoStart).navigationBarTitleDisplayMode(.inline).navigationTitle("Custom")
                } label: {
                    wayLabel("Custom", detail: "앱이 카메라를 쥐고 SDK 세션에 프레임을 넘긴다. 줌은 SDK 권고를 앱이 건다.")
                }

                // 시작 방식 — 두 길 모두에 건다.
                Toggle(isOn: $autoStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("자동 시작").font(.headline)
                        Text("켜면 측정 화면이 열리자마자 버튼 없이 시작한다(비대화형). 끄면 버튼을 눌러 시작한다(대화형).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let licenseError {
                    Text("라이선스 검증 실패 — \(licenseError)")
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .navigationViewStyle(.stack)
    }

    private func wayLabel(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.title3.bold())
            Text(detail).font(.caption).multilineTextAlignment(.center).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
    }
}
