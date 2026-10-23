import SwiftUI

/// 신호 그래프(signalTrace). **비어 있으면 비워 둔다** — 측정을 시작한 직후에는 SDK 가 아직 내지 않는다.
/// 그래프 신호는 30Hz 로 바뀌므로 이 조각만 `signal` 을 본다.
struct MeasureSignalBox: View {
    @ObservedObject var signal: SampleSignalState

    var body: some View {
        SignalChart(samples: signal.samples)
            .frame(height: 80)
            // 카메라 영상 위에 얹히므로 흰색 5% 로는 그래프가 묻힌다.
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// rPPG 신호 그래프 — 창 안의 최소~최대로 맞추고 큰 값을 위로 그린다.
private struct SignalChart: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard samples.count > 1 else { return }
                let minValue = samples.min() ?? 0
                let maxValue = samples.max() ?? 1
                let span = max(maxValue - minValue, 0.0001)
                let stepX = geo.size.width / CGFloat(samples.count - 1)

                for (index, sample) in samples.enumerated() {
                    let normalized = (sample - minValue) / span
                    let point = CGPoint(x: CGFloat(index) * stepX,
                                        y: geo.size.height * (1 - CGFloat(normalized)))
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
            }
            .stroke(Color.green, lineWidth: 1.5)
        }
        .padding(6)
    }
}
