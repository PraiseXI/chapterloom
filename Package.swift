// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Chapterloom",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Chapterloom", targets: ["Chapterloom"])],
    targets: [
        .executableTarget(name: "Chapterloom", path: "Sources/Chapterloom"),
        .testTarget(name: "ChapterloomTests", dependencies: ["Chapterloom"], path: "Tests/ChapterloomTests"),
    ]
)
