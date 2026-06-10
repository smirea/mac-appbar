// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAppBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacAppBar", targets: ["MacAppBar"])
    ],
    targets: [
        .executableTarget(name: "MacAppBar")
    ]
)
