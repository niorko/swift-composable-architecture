// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "swift-composable-architecture",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(
      name: "ComposableArchitecture",
      targets: ["ComposableArchitecture"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.1.3"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "0.1.0"),
    .package(url: "https://github.com/mxcl/PromiseKit", from: "7.0.0-rc2")
  ],
  targets: [
    .target(
      name: "ComposableArchitecture",
      dependencies: [
        "CasePaths",
        "XCTestDynamicOverlay",
        "PromiseKit"
      ]
    ),
    .testTarget(
      name: "ComposableArchitectureTests",
      dependencies: [
        "ComposableArchitecture"
      ]
    ),
  ]
)
