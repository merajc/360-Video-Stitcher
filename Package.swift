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
            path: "Sources/GoPro360Stitcher",
            // Shipped as a plain resource (not a .metal build input) and compiled at
            // runtime via MTLLibrary.makeLibrary(source:). This keeps `swift build`
            // working on machines without the optional Xcode 26 "Metal Toolchain".
            resources: [
                .copy("EACShader.msl")
            ]
        )
    ]
)
