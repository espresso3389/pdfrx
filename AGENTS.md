# AGENTS.md

This file provides guidance to AI agents and developers when working with code in this repository.

## Quick Start for Agents

- Keep existing user changes intact; if you notice unexpected edits you didn't make, pause and ask the user how to proceed.
- Prefer fast, non-destructive tools (`rg`, `rg --files`, targeted tests) and run commands with an explicit `workdir`; avoid wandering `cd` commands.
- Leave release artifacts (`CHANGELOG.md`, version numbers, tags) untouched unless the task is explicitly about publishing.
- Default to ASCII output and add only brief clarifying comments when the code is non-obvious.

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

## Command and Tooling Expectations

- Run commands directly in the repository environment with the correct `workdir`; coordinate with the user before escalating privileges or leaving the workspace.
- Prefer `rg`/`rg --files` for search and discovery tasks; they are significantly faster than alternatives.
- Use Flutter/Dart tooling for formatting (`dart format`, `flutter format`) and keep the 120 character width.
- On Windows, use `pwsh.exe -Command ...` if a command fails due to script launching quirks.

### Pub Workspace Basics

This project uses a pub workspace. Running `dart pub get` in any directory inside the repository fetches dependencies for all packages.

### Common Commands

```bash
# Flutter plugin (packages/pdfrx)
cd packages/pdfrx
flutter pub get
flutter analyze
flutter test
flutter format .

# Core engine (packages/pdfrx_engine)
cd packages/pdfrx_engine
dart pub get
dart analyze
dart test
dart format .
```

### Platform Builds

```bash
cd packages/pdfrx/example/viewer
flutter run
flutter build appbundle
flutter build ios
flutter build web --wasm
flutter build linux
flutter build windows
flutter build macos
```

### FFI Bindings

FFI bindings for PDFium are maintained in the `pdfium_dart` package and generated using `ffigen`.

#### Prerequisites

The `ffigen` process requires the following prerequisites to be installed:

- **LLVM/Clang**: Required for parsing C headers
  - macOS: Install via Homebrew: `brew install llvm`
  - Linux: Install via package manager: `apt-get install libclang-dev` (Ubuntu/Debian) or `dnf install clang-devel` (Fedora)
  - Windows: Install LLVM from [llvm.org](https://releases.llvm.org/)

#### Generating Bindings

```bash
# For pdfium_dart package
cd packages/pdfium_dart
dart test  # Downloads PDFium headers automatically
dart run ffigen

# For pdfrx_engine (if needed)
cd packages/pdfrx_engine
dart test
dart run ffigen
```

#### On-Demand PDFium Downloads

The `pdfium_dart` package provides a `getPdfium()` function that downloads PDFium binaries on demand. This is useful for testing or CLI applications that don't want to bundle PDFium binaries.

## Release Process

See `RELEASING.md` for the full checklist. Agents should avoid editing release metadata unless the task explicitly covers publishing.

- Never bump versions or changelog entries preemptively.
- Surface blockers or uncertainties to the user before continuing a release flow.

## Architecture Overview

For architectural details and API surface breakdowns, refer to:

- `README.md` for a high-level overview of both packages.
- `packages/pdfrx_engine/README.md` for engine internals and FFI notes.
- `packages/pdfrx/README.md` for Flutter plugin structure, widgets, and overlays.

These documents live alongside the code and stay in sync with implementation changes.

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
