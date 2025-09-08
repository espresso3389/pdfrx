# AGENTS.md

This file provides guidance to AI agents and developers when working with code in this repository.

## Project Overview

pdfrx is a monorepo containing two packages:

1. **pdfrx_engine** (`packages/pdfrx_engine/`) - A platform-agnostic PDF rendering API built on top of PDFium
   - Pure Dart package with no Flutter dependencies
   - Provides core PDF document API and PDFium bindings
   - Can be used independently for non-Flutter Dart applications

2. **pdfrx** (`packages/pdfrx/`) - A cross-platform PDF viewer plugin for Flutter
   - Depends on pdfrx_engine for PDF rendering functionality
   - Provides Flutter widgets and UI components
   - Supports iOS, Android, Windows, macOS, Linux, and Web
   - Uses PDFium for native platforms and PDFium WASM for web platforms

## Development Commands

### Monorepo Management

This project uses pub workspace for managing the multi-package repository. All you have to do is to run `dart pub get` on somewhere in the repo directory.

### Basic Flutter Commands

```bash
# For the main pdfrx package
cd packages/pdfrx
flutter pub get          # Install dependencies
flutter analyze          # Run static analysis
flutter test             # Run all tests
flutter format .         # Format code (120 char line width)

# For the pdfrx_engine package
cd packages/pdfrx_engine
dart pub get            # Install dependencies
dart analyze            # Run static analysis
dart test               # Run all tests
dart format .           # Format code (120 char line width)
```

### Platform-Specific Builds

```bash
# Example app
cd packages/pdfrx/example/viewer
flutter run              # Run on connected device/emulator
flutter build appbundle  # Build Android App Bundle
flutter build ios        # Build iOS (requires macOS)
flutter build web --wasm # Build for web
flutter build linux      # Build for Linux
flutter build windows     # Build for Windows
flutter build macos      # Build for macOS
```

### FFI Bindings Generation (pdfrx_engine)

- FFI bindings for PDFium are generated using `ffigen` in the pdfrx_engine package.
- FFI bindings depends on the Pdfium headers which are downloaded during `dart test` on pdfrx_engine (Linux only).

```bash
# Run on Linux
cd packages/pdfrx_engine
dart test
dart run ffigen          # Regenerate PDFium FFI bindings
```

## Release Process

Both packages may need to be released when changes are made:

### For pdfrx_engine package updates

1. Update version in `packages/pdfrx_engine/pubspec.yaml`
   - Basically, if the changes are not breaking (or relatively small breaking changes), increment the patch version (X.Y.Z -> X.Y.Z+1)
   - If there are breaking changes, increment the minor version (X.Y.Z -> X.Y+1.0)
   - If there are major changes, increment the major version (X.Y.Z -> X+1.0.0)
2. Update `packages/pdfrx_engine/CHANGELOG.md` with changes
   - Don't mention CI/CD changes and `CLAUDE.md`/`AGENTS.md` related changes (unless they are significant)
3. Update `packages/pdfrx_engine/README.md` if needed
4. Update `README.md` on the repo root if needed
5. Run `dart pub publish` in `packages/pdfrx_engine/`

### For pdfrx package updates

1. Update version in `packages/pdfrx/pubspec.yaml`
   - If pdfrx_engine was updated, update the dependency version
2. Update `packages/pdfrx/CHANGELOG.md` with changes
3. Update `packages/pdfrx/README.md` with new version information
   - Changes version in example fragments
   - Consider to add notes for new features or breaking changes
   - Notify the owner if you find any issues with the example app or documentation
4. Update `README.md` on the repo root if needed
5. Run `dart pub get` to update all dependencies
6. Run tests to ensure everything works
   - Run `dart test` in `packages/pdfrx_engine/`
   - Run `flutter test` in `packages/pdfrx/`
7. Ensure the example app builds correctly
   - Run `flutter build web --wasm` in `packages/pdfrx/example/viewer` to test the example app
8. Commit changes with message "Release pdfrx vX.Y.Z" or "Release pdfrx_engine vX.Y.Z"
9. Tag the commit with `git tag pdfrx-vX.Y.Z` or `git tag pdfrx_engine-vX.Y.Z`
10. Push changes and tags to remote
11. Run `flutter pub publish` in `packages/pdfrx/`
12. If the changes reference GitHub issues or PRs, add comments on them notifying about the new release
    - Use `gh issue comment` or `gh pr comment` to notify that the issue/PR has been addressed in the new release
    - If the PR references issues, please also comment on the issues
    - Follow the template below for comments (but modify it as needed):

      ```md
      The FIX|UPDATE|SOMETHING for this issue has been released in v[x.y.z](https://pub.dev/packages/pdfrx/versions/x.y.z).

      ...Fix/update summary...

      Written by [AGENT SIGNATURE]
      ```

    - Focus on the release notes and what was fixed/changed rather than upgrade instructions
    - Include a link to the changelog for the specific version

## Architecture Overview

### Package Architecture

The project is split into two packages with clear separation of concerns:

#### pdfrx_engine (`packages/pdfrx_engine/`)

- Platform-agnostic PDF rendering engine
- Conditional imports to support different platforms:
  - `lib/src/native/` - Native platform implementation using PDFium via FFI
  - `lib/src/web/` - Web implementation using PDFium WASM
  - Platform-specific code determined at import time based on `dart:library.io` availability
- Main exports:
  - `pdf_api.dart` - Core PDF document interfaces

#### pdfrx (`packages/pdfrx/`)

- Flutter plugin built on top of pdfrx_engine
- Contains all Flutter-specific code:
  - Widget layer
  - Platform channel implementations
  - UI components and overlays

### Core Components

1. **Document API** (in `packages/pdfrx_engine/lib/src/pdf_api.dart`)
   - `PdfDocument` - Main document interface
   - `PdfPage` - Page representation
   - `PdfDocumentRef` - Reference counting for document lifecycle
   - Platform-agnostic interfaces implemented differently per platform

2. **Widget Layer** (in `packages/pdfrx/lib/src/widgets/`)
   - `PdfViewer` - Main viewer widget with multiple constructors
   - `PdfPageView` - Single page display
   - `PdfDocumentViewBuilder` - Safe document loading pattern
   - Overlay widgets for text selection, links, search

3. **Native Integration**
   - pdfrx_engine uses Dart FFI for PDFium integration
   - Native code in `packages/pdfrx_engine/src/pdfium_interop.cpp`
   - Platform folders in `packages/pdfrx/` contain Flutter plugin build configurations

### Key Patterns

- **Factory Pattern**: `PdfDocumentFactory` creates platform-specific implementations
- **Builder Pattern**: `PdfDocumentViewBuilder` for safe async document loading
- **Overlay System**: Composable overlays for text, links, annotations
- **Conditional Imports**: Web vs native determined at compile time

## Testing

Tests download PDFium binaries automatically for supported platforms. Run tests with:

```bash
# Test pdfrx_engine
cd packages/pdfrx_engine
dart test

# Test pdfrx Flutter plugin
cd packages/pdfrx
flutter test
```

## Platform-Specific Notes

### iOS/macOS

- Uses pre-built PDFium binaries from [GitHub releases](https://github.com/espresso3389/pdfrx/releases)
- CocoaPods integration via `packages/pdfrx/darwin/pdfrx.podspec`
- Binaries downloaded during pod install (Or you can use Swift Package Manager if you like)

### Android

- Uses CMake for native build
- Requires Android NDK
- Downloads PDFium binaries during build

### Web

- `packages/pdfrx/assets/pdfium.wasm` is prebuilt PDFium WASM binary
- `packages/pdfrx/assets/pdfium_worker.js` is the worker script that contains Pdfium WASM's shim
- `packages/pdfrx/assets/pdfium_client.js` is the code that launches the worker and provides the API, which is used by pdfrx_engine's web implementation

### Windows/Linux

- CMake-based build
- Downloads PDFium binaries during build

## Code Style

- Single quotes for strings
- 120 character line width
- Relative imports within lib/
- Follow flutter_lints with custom rules in analysis_options.yaml

## Dependency Version Policy

### pdfrx_engine

This package follows standard Dart package versioning practices.

### pdfrx

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

- Include links to issues/PRs when relevant; `#NNN` -> `[#NNN](https://github.com/espresso3389/pdfrx/issues/NNN)`
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
