// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Clipward",
    platforms: [.macOS(.v10_13)],
    products: [
        .executable(name: "Clipward", targets: ["Clipward"]),
    ],
    targets: [
        .target(name: "ClipwardCore"),
        .executableTarget(name: "Clipward", dependencies: ["ClipwardCore"]),
    ]
)
