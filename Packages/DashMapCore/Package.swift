// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DashMapCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DashMapCore", targets: ["DashMapCore"])],
    targets: [
        .target(name: "DashMapCore"),
        .testTarget(name: "DashMapCoreTests", dependencies: ["DashMapCore"]),
    ]
)
