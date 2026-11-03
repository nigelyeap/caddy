// swift-tools-version:6.0
import PackageDescription

// One target per owner so a half-finished target never breaks another's build.
let package = Package(
    name: "CADDY",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CADDY", targets: ["CADApp"])],
    targets: [
        .target(name: "CADShared"),
        .target(name: "CADBackend", dependencies: ["CADShared"]),
        .target(name: "CADScan", dependencies: ["CADShared"]),
        .target(name: "CADViewer", dependencies: ["CADShared"]),
        .target(name: "CADGesture", dependencies: ["CADShared"]),
        .executableTarget(name: "CADApp", dependencies: ["CADShared", "CADBackend", "CADScan", "CADViewer", "CADGesture"],
                          resources: [.copy("Resources/mug.stl"), .copy("Resources/turntable_sample.txt"), .copy("Resources/Caddy")]),
        .testTarget(name: "CADScanTests", dependencies: ["CADScan", "CADShared"]),
        .testTarget(name: "CADAppTests", dependencies: ["CADApp", "CADShared", "CADBackend"]),
        .testTarget(name: "CADViewerTests", dependencies: ["CADViewer"]),
        .testTarget(name: "CADGestureTests", dependencies: ["CADGesture"]),
    ],
    swiftLanguageModes: [.v5]
)
