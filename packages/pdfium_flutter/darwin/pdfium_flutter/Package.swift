// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "pdfium_flutter",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13),
    ],
    products: [
        .library(
            name: "pdfium-flutter",
            targets: ["pdfium_flutter"]
        ),
    ],
    targets: [
        .target(
            name: "pdfium_flutter",
            dependencies: [
                .target(name: "PDFium"),
            ],
            path: "Sources/main"
        ),
        .binaryTarget(
            name: "PDFium",
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7520.0-20251111-190355/PDFium-chromium-7520-20251111-190355.xcframework.zip",
            checksum: "bd2a9542f13c78b06698c7907936091ceee2713285234cbda2e16bc03c64810b"
        ),
    ]
)
