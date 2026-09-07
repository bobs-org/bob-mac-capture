// swift-tools-version: 6.0

import PackageDescription

// AppKit lives only on macOS. Linux hosts still build and test CaptureCore, which is
// the process-client/JSON contract the app depends on.
#if os(macOS)
let macCaptureProducts: [Product] = [
    .executable(
        name: "BobMacCapture",
        targets: ["BobMacCapture"]
    ),
    .executable(
        name: "BobMacCaptureInstallHelper",
        targets: ["BobMacCaptureInstallHelper"]
    ),
]
let macCaptureTargets: [Target] = [
    .executableTarget(
        name: "BobMacCapture",
        dependencies: ["CaptureCore"],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ]
    ),
    .testTarget(
        name: "BobMacCaptureTests",
        dependencies: ["BobMacCapture", "CaptureCore"],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ]
    ),
    .executableTarget(
        name: "BobMacCaptureInstallHelper",
        dependencies: ["CaptureCore"],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ]
    ),
    .testTarget(
        name: "BobMacCaptureInstallHelperTests",
        dependencies: ["BobMacCaptureInstallHelper", "CaptureCore"],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ]
    ),
]
#else
let macCaptureProducts: [Product] = []
let macCaptureTargets: [Target] = []
#endif

let package = Package(
    name: "BobMacCapture",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "CaptureCore",
            targets: ["CaptureCore"]
        )
    ] + macCaptureProducts,
    targets: [
        .target(
            name: "CaptureCore",
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
    ] + macCaptureTargets
)
