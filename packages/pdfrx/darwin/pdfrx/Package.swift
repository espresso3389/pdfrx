// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "pdfrx",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_11)
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
                .target(name: "pdfium", condition: .when(platforms: [.iOS])),
                .target(name: "pdfium-macos", condition: .when(platforms: [.macOS]))
            ]
        ),
        .binaryTarget(
            name: "pdfium",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v10/pdfium-ios.zip",
            checksum: "d716939a98f8a27a84eb463e62aee91c42a8f11ab50d49f4698c56195b728727"
        ),
        .binaryTarget(
            name: "pdfium-macos",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v10/pdfium-macos.zip",
            checksum: "dd7d79041554c1dafe24008cb7d5c4f3a18977953ef38fa8756338fa2b7bd9ab"
        )
    ]
)
