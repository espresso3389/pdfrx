
// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "pdfrx",
    platforms: [
        .iOS("12.0"),
        .macOS("10.11")
    ],
    products: [
        .library(name: "pdfrx", targets: ["pdfrx"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "pdfrx",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include/pdfrx")
            ]
        )
    ]
)
