// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MailEdgeMac",
  defaultLocalization: "zh-Hans",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "MailEdge", targets: ["MailEdgeApp"])
  ],
  targets: [
    .executableTarget(
      name: "MailEdgeApp",
      path: "Sources/MailEdgeApp",
      resources: [.process("Resources")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "MailEdgeAppTests",
      dependencies: ["MailEdgeApp"],
      path: "Tests/MailEdgeAppTests"
    ),
  ]
)
