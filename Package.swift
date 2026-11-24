// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FreeMacOn", platforms: [.macOS(.v13)],
    products: [.executable(name: "FreeMacOn", targets: ["FreeMacOn"])],
    targets: [
        .target(name: "FreeMacOnCore"),
        .executableTarget(name: "FreeMacOn", dependencies: ["FreeMacOnCore"]),
        .testTarget(name: "FreeMacOnCoreTests", dependencies: ["FreeMacOnCore"])
    ]
)
