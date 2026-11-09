// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ibkr",
    platforms: [.macOS(.v13)],
    products: [.library(name: "IBKR", targets: ["IBKR"])],
    targets: [
        .target(name: "IBKR"),
        .testTarget(name: "IBKRTests", dependencies: ["IBKR"]),
    ]
)
