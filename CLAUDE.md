# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pdfrx is a cross-platform PDF viewer plugin for Flutter that supports iOS, Android, Windows, macOS, Linux, and Web. It uses PDFium for native platforms and supports both PDF.js and PDFium WASM for web platforms.

## Development Commands

### Basic Flutter Commands

```bash
flutter pub get          # Install dependencies
flutter analyze          # Run static analysis
flutter test             # Run all tests
flutter format .         # Format code (120 char line width)
```

### Platform-Specific Builds

```bash
# Example app
cd example/viewer
flutter run              # Run on connected device/emulator
flutter build appbundle  # Build Android App Bundle
flutter build ios        # Build iOS (requires macOS)
flutter build web --wasm # Build for web
flutter build linux      # Build for Linux
flutter build windows     # Build for Windows
flutter build macos      # Build for macOS
```

### FFI Bindings Generation

- FFI bindings for PDFium are generated using `ffigen`.
- FFI bindings depends on the Pdfium headers installed on `example/viewer/build/linux/x64/release/.lib/latest/include`
  - The headers are downloaded automatically during the build process; `flutter build linux` must be run at least once

```bash
cd example/viewer && flutter build linux
dart run ffigen          # Regenerate PDFium FFI bindings
```

## Release Process

1. Update version in `pubspec.yaml`
   - Basically, if the changes are not breaking (or relatively small breaking changes), increment the patch version (X.Y.Z -> X.Y.Z+1)
   - If there are breaking changes, increment the minor version (X.Y.Z -> X.Y+1.0)
   - If there are major changes, increment the major version (X.Y.Z -> X+1.0.0)
2. Update `CHANGELOG.md` with changes
   - Don't mention CI/CD changes and `CLAUDE.md` related changes (unless they are significant)
3. Update `README.md` with new version information
   - Changes version in example fragments
   - Consider to add notes for new features or breaking changes
   - Notify the owner if you find any issues with the example app or documentation
4. Run `flutter pub get` on all affected directories
   - This includes the main package, example app, and wasm package if applicable
   - Ensure all dependencies are resolved and up-to-date
5. Run tests to ensure everything works
   - Run `flutter test` to execute all tests on root directory (not in `example/viewer`)
6. Ensure the example app builds correctly
   - Run `flutter build web --wasm` in `example/viewer` to test the example app
7. Commit changes with message "Release vX.Y.Z"
8. Tag the commit with `git tag vX.Y.Z`
9. Push changes and tags to remote
10. Do `flutter pub publish` to publish the package
11. If the changes reference GitHub issues or PRs, add comments on them notifying about the new release
    - Use `gh issue comment` or `gh pr comment` to notify that the issue/PR has been addressed in the new release
    - If the PR references issues, please also comment on the issues
    - Follow the template below for comments (but modify it as needed):

      ```
      The FIX|UPDATE|SOMETHING for this issue has been released in v[x.y.z](https://pub.dev/packages/pdfrx/versions/x.y.z).

      ...Fix/update summary...

      Written by 🤖[Claude Code](https://claude.ai/code)
      ```

    - Focus on the release notes and what was fixed/changed rather than upgrade instructions
    - Include a link to the changelog for the specific version

## Architecture Overview

### Platform Abstraction

The plugin uses conditional imports to support different platforms:

- `lib/src/pdfium/` - Native platform implementation using PDFium via FFI
- `lib/src/web/` - Web implementation by PDFium WASM
- Platform-specific code determined at import time based on `dart:library.io` availability

### Core Components

1. **Document API** (`lib/src/pdf_api.dart`)
   - `PdfDocument` - Main document interface
   - `PdfPage` - Page representation
   - `PdfDocumentRef` - Reference counting for document lifecycle
   - Platform-agnostic interfaces implemented differently per platform

2. **Widget Layer** (`lib/src/widgets/`)
   - `PdfViewer` - Main viewer widget with multiple constructors
   - `PdfPageView` - Single page display
   - `PdfDocumentViewBuilder` - Safe document loading pattern
   - Overlay widgets for text selection, links, search

3. **Native Integration**
   - Uses Flutter FFI for PDFium integration
   - Native code in `src/pdfium_interop.cpp`
   - Platform folders contain build configurations

### Key Patterns

- **Factory Pattern**: `PdfDocumentFactory` creates platform-specific implementations
- **Builder Pattern**: `PdfDocumentViewBuilder` for safe async document loading
- **Overlay System**: Composable overlays for text, links, annotations
- **Conditional Imports**: Web vs native determined at compile time

## Testing

Tests download PDFium binaries automatically for supported platforms. Run tests with:

```bash
flutter test
flutter test test/pdf_document_test.dart  # Run specific test file
```

## Platform-Specific Notes

### iOS/macOS

- Uses pre-built PDFium binaries from [GitHub releases](https://github.com/espresso3389/pdfrx/releases)
- CocoaPods integration via `darwin/pdfrx.podspec`
- Binaries downloaded during pod install (Or you can use Swift Package Manager if you like)

### Android

- Uses CMake for native build
- Requires Android NDK
- Downloads PDFium binaries during build

### Web

- `assets/pdfium.wasm` is prebuilt PDFium WASM binary
- `assets/pdfium_worker.js` is the worker script that contains Pdfium WASM's shim
- `assets/pdfium_client.js` is the code that launches the worker and provides the API, which is used by `lib/src/web/pdfrx_wasm.dart`

### Windows/Linux

- CMake-based build
- Downloads PDFium binaries during build

## Code Style

- Single quotes for strings
- 120 character line width
- Relative imports within lib/
- Follow flutter_lints with custom rules in analysis_options.yaml

## Dependency Version Policy

This package intentionally does NOT specify version constraints for core Flutter-managed packages (collection, ffi, http, path, rxdart). This design decision allows:

- Flutter SDK to manage these dependencies based on the user's Flutter version
- Broader compatibility across different Flutter stable versions
- Avoiding version conflicts for users on older Flutter stable releases

When running `flutter pub publish`, warnings about missing version constraints for these packages can be safely ignored. Only packages that are not managed by Flutter SDK should have explicit version constraints.

## Documentation Guidelines

The following guidelines should be followed when writing documentation including comments, `README.md`, and other markdown files:

- Use proper grammar and spelling
- Use clear and concise language
- Use consistent terminology
- Use proper headings for sections
- Use code blocks for code snippets
- Use bullet points for lists
- Use link to relevant issues/PRs when applicable
- Use backticks (`` ` ``) for code references and file/directory/path names in documentation

### Commenting Guidelines

- Use reference links for classes, enums, and functions in documentation
- Use `///` (dartdoc comments) for public API comments (and even for important private APIs)

### Markdown Documentation Guidelines

- Include links to issues/PRs when relevant
- Use link to [API reference](https://pub.dev/documentation/pdfrx/latest/pdfrx/) for public APIs if possible
- `README.md` should provide an overview of the project, how to use it, and any important notes
- `CHANGELOG.md` should follow the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) principles
  - Be careful not to include implementation details in the changelog
  - Focus on user-facing changes, new features, bug fixes, and breaking changes
  - Use sections for different versions
  - Use bullet points for changes

## Special Notes

- `CHANGELOG.md` is not an implementation node. So it should be updated only on releasing a new version
- For web search, if `gemini` command is available, use `gemini -p "<query>"`.
