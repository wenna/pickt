// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pickt",
    platforms: [.iOS("15.5"), .macOS(.v12)],
    products: [.library(name: "PicktCore", targets: ["PicktCore"])],
    targets: [
        .target(name: "PicktCore"),
        .testTarget(name: "PicktCoreTests", dependencies: ["PicktCore"])
    ]
)
