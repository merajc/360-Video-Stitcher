// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoPro360Stitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GoPro360Stitcher", targets: ["GoPro360Stitcher"])
    ],
    targets: [
        .executableTarget(
            name: "GoPro360Stitcher",
            path: "Sources/GoPro360Stitcher"
        )
    ]
)
