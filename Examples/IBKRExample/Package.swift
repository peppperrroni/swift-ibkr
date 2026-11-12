// swift-tools-version: 6.0
import PackageDescription

// The dependency's identity is the repository folder's name, `swift-ibkr` in a default clone and in CI.
let package = Package(
    name: "IBKRExample",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "ibkr-example", dependencies: [.product(name: "IBKR", package: "swift-ibkr")]),
    ]
)
