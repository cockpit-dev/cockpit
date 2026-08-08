// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "flutter_cockpit",
  platforms: [
    .macOS("10.15"),
  ],
  products: [
    .library(name: "flutter-cockpit", targets: ["flutter_cockpit"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "flutter_cockpit",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy"),
      ]
    ),
  ]
)
