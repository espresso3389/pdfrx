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
            targets: ["PDFium"]
        ),
    ],
    targets: [
        .target(
            name: "pdfrx",
            dependencies: [
                .target(name: "PDFium"),
            ]
        ),
        .binaryTarget(
            name: "PDFium",
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7506.0/PDFium-chromium-7506-20251109-174316.xcframework.zip",
            checksum: "b114cd6b6cc52bff705e9b705b450f83bc014b146f6fa532f37177b5c8f4b030"
        ),
    ]
)
