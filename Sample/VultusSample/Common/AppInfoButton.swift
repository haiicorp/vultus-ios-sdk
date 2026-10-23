import SwiftUI
import Vultus

/// 앱 정보 버튼 — 누르면 설치 식별자와 SDK 버전을 띄운다.
///
/// 식별자 · 버전은 팝업으로 뺐다. 프리뷰를 가리는 것이 적을수록 자세를 잡기 쉽고, 이 둘은 측정 중에 볼 값이
/// 아니라 사후에 대조할 값이다.
struct AppInfoButton: View {
    @State private var infoShown = false

    var body: some View {
        Button {
            infoShown = true
        } label: {
            Image(systemName: "info.circle")
                .font(.headline)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("앱 정보")
        // 배포 타깃이 iOS 15 라 `presentationDetents` 를 무조건 붙일 수 없다.
        // 15 에서는 시트가 전체 높이로 뜬다 — 기능은 같다.
        .sheet(isPresented: $infoShown) {
            if #available(iOS 16.0, *) {
                infoSheet.presentationDetents([.height(260)])
            } else {
                infoSheet
            }
        }
    }

    /// 설치 식별자와 SDK 버전.
    ///
    /// `installationId` 는 측정 meta 의 appendix 로도 함께 나가므로 서버 기록과 맞춰
    /// 볼 수 있다. **그래서 복사할 수 있어야 한다** — 눈으로 옮겨 적다 틀리면 엉뚱한
    /// 세션을 본다. alert 이 아니라 sheet 을 쓰는 이유가 그것이다.
    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("앱 정보").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("SampleAppIdentifier").font(.caption2).foregroundStyle(.secondary)
                Text(InstallationId.current).font(.callout.bold())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Vultus").font(.caption2).foregroundStyle(.secondary)
                Text(Vultus.sdkVersion).font(.callout.bold())
            }

            Spacer()

            Button("닫기") { infoShown = false }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
        }
        .textSelection(.enabled)
        .padding()
    }
}
