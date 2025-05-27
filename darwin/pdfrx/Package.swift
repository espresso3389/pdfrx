
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
            dependencies: [
                .target(name: "PDFium", condition: .when(platforms: [.iOS])),
                .target(name: "PDFiumMacOS", condition: .when(platforms: [.macOS]))
            ],
            cSettings: [
                .headerSearchPath("include/pdfrx")
            ]
        ),
        .binaryTarget(
            name: "PDFium",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v9/pdfium-ios.zip",
            checksum: "PLACEHOLDER_IOS_ZIP_CHECKSUM"
        ),
        .binaryTarget(
            name: "PDFiumMacOS",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v9/pdfium-macos.zip",
            checksum: "PLACEHOLDER_MACOS_ZIP_CHECKSUM"
        )
    ]
)
