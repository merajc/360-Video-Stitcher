// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "360VideoStitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Binary name: 360VideoStitcher. The Swift target is Stitcher360 because a
        // module name cannot start with a digit.
        .executable(name: "360VideoStitcher", targets: ["Stitcher360"])
    ],
    targets: [
        .executableTarget(
            name: "Stitcher360",
            path: "Sources/Stitcher360",
            // Shipped as a plain resource (not a .metal build input) and compiled at
            // runtime via MTLLibrary.makeLibrary(source:). This keeps `swift build`
            // working on machines without the optional Xcode 26 "Metal Toolchain".
            resources: [
                .copy("EACShader.msl")
            ]
        )
    ]
)
