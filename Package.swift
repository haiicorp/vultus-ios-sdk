// swift-tools-version: 5.9
import PackageDescription

// =============================================================================
// Vultus iOS SDK — 배포 패키지
//
// 배포 패키지 매니페스트다. 직접 고치면 판올림 때 덮어써진다.
//
// Vultus 는 사전 빌드한 동적 프레임워크 하나다. 검출기도 SDK 에 내장되어 있어 별도 의존성이 없다.
// =============================================================================

let package = Package(
    name: "Vultus",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "Vultus", targets: ["Vultus"])
    ],
    targets: [
        // 릴리스 자산으로 배포되는 사전 빌드 프레임워크. checksum 은 zip 바이트에
        // 대해 계산되므로 자산을 교체하면 이 값도 함께 갱신해야 한다.
        .binaryTarget(
            name: "Vultus",
            url: "https://github.com/haiicorp/vultus-ios-sdk/releases/download/1.0.0/Vultus.xcframework.zip",
            checksum: "5d00773b14bc9d5408682dd83656534a8ce55112911f5757642c426482b9b710"
        ),
    ]
)
