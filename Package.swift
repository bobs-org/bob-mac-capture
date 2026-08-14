// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BobMacCapture",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "CaptureCore",
            targets: ["CaptureCore"]
        ),
        .executable(
            name: "BobMacCapture",
            targets: ["BobMacCapture"]
        ),
    ],
    targets: [
        .target(
            name: "CaptureCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "BobMacCapture",
            dependencies: ["CaptureCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CaptureCoreTests",
            dependencies: ["CaptureCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "BobMacCaptureTests",
            dependencies: ["BobMacCapture"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
