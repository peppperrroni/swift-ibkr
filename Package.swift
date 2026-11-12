// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ibkr",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "IBKR", targets: ["IBKR"]), .library(name: "IBKRFlex", targets: ["IBKRFlex"])],
    targets: [
        .target(name: "IBKR"),
        .target(name: "IBKRFlex"),
        .testTarget(name: "IBKRTests", dependencies: ["IBKR"], exclude: ["Recorded"]),
        .testTarget(name: "IBKRFlexTests", dependencies: ["IBKRFlex"]),
    ]
)
