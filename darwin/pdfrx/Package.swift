
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
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v9/pdfium-ios.tgz",
            checksum: "7cea37346faeaafed72bfc1a0ac989eab9fe3a0693c6f9adda6deb6f6f93661d"
        ),
        .binaryTarget(
            name: "PDFiumMacOS",
            url: "https://github.com/espresso3389/pdfrx/releases/download/pdfium-apple-v9/pdfium-macos.tgz",
            checksum: "449ef5772721aea739a678da56130071bbd7d663132299240e812931fd7ddb7b"
        )
    ]
)
