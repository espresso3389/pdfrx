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
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7520.0-20251111-173323/PDFium-chromium-7520-20251111-173323.xcframework.zip",
            checksum: "fb1419cadda3fbae9953bdcb1cc358fdeb7d10f80141e3c3d03be4dfd1f18b53"
        ),
    ]
)
