// swift-tools-version:5.6
import PackageDescription

let package = Package(
  name: "pdfrx_coregraphics",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_13)
  ],
  products: [
    .library(
      name: "pdfrx-coregraphics",
      targets: ["pdfrx_coregraphics"]
    )
  ],
  targets: [
    .target(
      name: "pdfrx_coregraphics",
      dependencies: [],
      path: ".",
      sources: ["Sources"]
    )
  ]
)
