// swift-tools-version:5.9
// CrushKit holds the rules of Margerum Crush: ripening, weather, the picking
// round, the crush pad, blending and the critic. It has no UI and no iOS
// dependencies, so `swift test` runs on macOS and Linux.
import PackageDescription

let package = Package(
    name: "CrushKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CrushKit", targets: ["CrushKit"]),
    ],
    targets: [
        .target(name: "CrushKit"),
        .testTarget(name: "CrushKitTests", dependencies: ["CrushKit"]),
    ]
)
