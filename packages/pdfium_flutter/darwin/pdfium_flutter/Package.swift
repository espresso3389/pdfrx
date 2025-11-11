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
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7520.0-20251111-181257/PDFium-chromium-7520-20251111-181257.xcframework.zip",
            checksum: "1190e2034a34f1f4a462e3564516750d6652b05064c545978306032bcd19be42"
        ),
    ]
)
