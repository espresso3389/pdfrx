## 0.2.0

- Updated to `pdfium_dart` 0.2.0.
- Updated native PDFium binaries to chromium/7811.
- Updated the iOS/macOS PDFium XCFramework build to chromium/7811.
- Delegated PDFium runtime loading to `pdfium_dart.getPdfium()`.
- Added native-assets link-hook metadata so iOS/macOS Flutter apps use the PDFium XCFramework without bundling a duplicate `libpdfium.dylib`.
- Improved native platform packaging:
  - Android, Linux, and Windows use Dart native assets.
  - iOS and macOS continue to use the PDFium XCFramework through CocoaPods or Swift Package Manager.
- Fixed link-hook handling for Flutter Web and other non-code-asset builds.

## 0.1.9

- FIXED: Inconsistent environment constraints - Flutter version now correctly requires 3.35.1+ to match Dart 3.9.0 requirement ([#553](https://github.com/espresso3389/pdfrx/issues/553))

## 0.1.8

- Dependency configuration updates.

## 0.1.7

- Documentation updates.

## 0.1.6

- Updated PDFium to version 144.0.7520.0 for Android, Linux, and Windows platforms.
- Updated `pdfium_dart` dependency to ^0.1.2.

## 0.1.5

- Updated PDFium to version 144.0.7520.0 (build 20251111-190355).

## 0.1.4

- Updated PDFium to version 144.0.7520.0 (build 20251111-183119).

## 0.1.3

- Updated PDFium to version 144.0.7520.0 (build 20251111-181257).

## 0.1.2

- Updated PDFium to version 144.0.7520.0 (build 20251111-173323).

## 0.1.1

- Fixed SwiftPM package name inconsistency.
- Several PDFium capitalization affecting API names

## 0.1.0

- First release.
