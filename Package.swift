// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TendCore",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
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
