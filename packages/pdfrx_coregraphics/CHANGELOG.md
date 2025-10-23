## 0.1.4

- Updated to pdfrx_engine 0.2.2
- Updated README example to remove explicit `WidgetsFlutterBinding.ensureInitialized()` call (now handled internally by `pdfrxFlutterInitialize()`)
- Implemented `PdfrxBackend` enum support

## 0.1.3

- **BREAKING**: Renamed `PdfrxEntryFunctions.initPdfium()` to `PdfrxEntryFunctions.init()` for consistency
- Updated README with documentation for `dart run pdfrx:remove_darwin_pdfium_modules` command to reduce app size
- Updated to pdfrx_engine 0.2.0

## 0.1.2

- Added Swift Package Manager (SwiftPM) support for easier integration
- Internal code structure reorganization and formatting improvements

## 0.1.1

- Initial CoreGraphics-backed Pdfrx entry implementation for iOS/macOS
