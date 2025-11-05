// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "pdfrx",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13),
    ],
    products: [
        .library(
            name: "pdfrx",
            targets: ["pdfrx"]
        ),
    ],
    targets: [
        .target(
            name: "pdfrx",
            dependencies: [
                .target(name: "pdfium"),
            ],
            path: "Sources/main"
        ),
        .target(
            name: "pdfium",
            dependencies: [
                .target(name: "pdfium-ios", condition: .when(platforms: [.iOS])),
                .target(name: "pdfium-macos", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/interop"
        ),
        .binaryTarget(
            name: "pdfium-ios",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v11/pdfium-ios.zip",
            checksum: "968e270318f9a52697f42b677ff5b46bde4da0702fb3930384d0a7f7e62c3073"
        ),
        .binaryTarget(
            name: "pdfium-macos",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v11/pdfium-macos.zip",
            checksum: "682ebbbb750fc185295e5b803f497e6ce25ab967476478253a1911977fe22c93"
        ),
    ]
)
