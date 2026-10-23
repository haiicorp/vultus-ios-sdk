import SwiftUI
import Vision
import Vultus

/// 얼굴 크기 색 — 지표와 오버레이가 같은 것을 쓴다. 크기 판단은 앱이 하지 않고 **SDK 의 촬영 조건**을 따른다 —
/// 문턱을 앱에 두면 SDK 의 안내와 어긋난다.
enum FaceSizeTarget {
    /// 촬영 조건의 원인에 대응하는 색. 너무 가깝거나 화면 밖에 걸리면 "가까이" 와 다른 색으로 알린다 — 색만 보고
    /// 더 다가오지 않게. 크기와 무관한 원인(얼굴 없음 · 자세 · 어두움)은 흰색이다.
    static func tint(_ cause: VultusCaptureCondition.Cause) -> Color {
        switch cause {
        case .none: return .green
        case .tooClose, .offFrame: return .orange
        case .tooFar, .framing: return .yellow
        default: return .white
        }
    }
}

/// 검출된 얼굴 bbox 와 랜드마크를 프리뷰 위에 그린다.
struct FaceOverlay: View {
    let face: VultusDetectedFace
    /// 프리뷰 뷰가 알려 준 변환(`onTransformChange`). 자동 맞춤의 배율 · 이동이 들어 있다.
    let transform: VultusPreviewTransform?
    let viewSize: CGSize
    /// 세션의 `effectiveOrientation` 의 `overlayRotationDegrees`.
    let rotationDegrees: Int
    /// SDK 촬영 조건의 원인 — 박스 색을 정한다.
    let captureCause: VultusCaptureCondition.Cause

    var body: some View {
        // 프리뷰 뷰의 변환을 그대로 쓴다 — 아직 받지 못했으면(첫 배치 전) 같은 산술로 만든다.
        let transform = self.transform.flatMap {
            $0.imageSize == CGSize(width: face.imageWidth, height: face.imageHeight) ? $0 : nil
        } ?? VultusPreviewTransform(imageSize: CGSize(width: face.imageWidth, height: face.imageHeight),
                                    viewSize: viewSize,
                                    fill: .fill,
                                    mirrored: true,
                                    rotationDegrees: rotationDegrees)
        let rect = transform.rect(face.boundingBox)

        ZStack {
            Path { $0.addRect(rect) }
                .stroke(FaceSizeTarget.tint(captureCause).opacity(0.9), lineWidth: 2)
            FaceLandmarkOverlay(face: face, transform: transform)
        }
    }
}

/// Vision 원본(`faceObservation`)의 랜드마크 영역 — 프레임 픽셀 좌표(원점 왼쪽 위)로 옮긴 점 묶음. Vision 은 0~1 정규화 · 원점
/// 왼쪽 아래라 그대로 그리면 위아래가 뒤집힌다. 눈 · 입술은 닫힌 윤곽이다.
enum FaceLandmarkRegions {
    static func of(_ face: VultusDetectedFace) -> [(points: [CGPoint], closed: Bool)] {
        guard let landmarks = face.faceObservation.landmarks else { return [] }
        let size = CGSize(width: face.imageWidth, height: face.imageHeight)
        let regions: [(VNFaceLandmarkRegion2D?, Bool)] = [
            (landmarks.faceContour, false), (landmarks.leftEyebrow, false), (landmarks.rightEyebrow, false),
            (landmarks.leftEye, true), (landmarks.rightEye, true), (landmarks.nose, false), (landmarks.noseCrest, false),
            (landmarks.medianLine, false), (landmarks.outerLips, true), (landmarks.innerLips, true),
        ]
        return regions.compactMap { region, closed in
            guard let region else { return nil }
            let points = region.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: size.height - $0.y) }
            return points.isEmpty ? nil : (points, closed)
        }
    }
}

/// 랜드마크 점(노랑)과 영역을 잇는 선(파랑). Vision 은 점이 많고 영역으로 묶여 있다.
struct FaceLandmarkOverlay: View {
    let face: VultusDetectedFace
    let transform: VultusPreviewTransform

    var body: some View {
        let regions = FaceLandmarkRegions.of(face).map { region in
            (points: region.points.map { transform.point($0) }, closed: region.closed)
        }
        ZStack {
            Path { path in
                for region in regions where region.points.count >= 2 {
                    path.addLines(region.points)
                    if region.closed { path.closeSubpath() }
                }
            }
            .stroke(Color.blue.opacity(0.8), lineWidth: 1)
            Path { path in
                for point in regions.flatMap(\.points) {
                    path.addEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
                }
            }
            .fill(Color.yellow)
        }
    }
}

