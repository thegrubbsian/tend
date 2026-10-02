// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "TendCore",
  platforms: [
    .iOS(.v27),
    .macOS(.v27),
  ],
  products: [
    .library(name: "TendCore", targets: ["TendCore"])
  ],
  dependencies: [],
  targets: [
    .target(name: "TendCore"),
    .testTarget(name: "TendCoreTests", dependencies: ["TendCore"]),
  ],
  swiftLanguageModes: [.v6]
)
