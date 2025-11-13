# Releasing Packages

This guide covers the full release checklist for all packages in the monorepo. Follow the steps that apply to the package you are releasing.

## Package Overview

The monorepo contains five packages:
- **pdfium_dart** - Low-level Dart FFI bindings for PDFium
- **pdfium_flutter** - Flutter plugin for loading PDFium native libraries
- **pdfrx_engine** - Platform-agnostic PDF rendering API
- **pdfrx** - Cross-platform PDF viewer plugin for Flutter
- **pdfrx_coregraphics** - CoreGraphics-backed renderer for iOS/macOS (experimental)

## pdfrx_engine Releases

1. Update the version in `packages/pdfrx_engine/pubspec.yaml`.
   - For non-breaking or small breaking changes, bump the patch version (`X.Y.Z -> X.Y.Z+1`).
   - For breaking changes, bump the minor version (`X.Y.Z -> X.Y+1.0`).
   - For major changes, bump the major version (`X.Y.Z -> X+1.0.0`).
2. Update `packages/pdfrx_engine/CHANGELOG.md` with user-facing changes.
   - Skip CI/CD updates and meta-doc changes (`CLAUDE.md`, `AGENTS.md`) unless significant.
3. Update `packages/pdfrx_engine/README.md` (at least, the versions hard-coded on it).
4. Update the root `README.md` if necessary.
5. Run `pana` inside `packages/pdfrx_engine` to validate the package.
6. Publish with `dart pub publish` inside `packages/pdfrx_engine/`.

## pdfrx Releases

1. Update the version in `packages/pdfrx/pubspec.yaml`.
   - If `pdfrx_engine` was updated, update the dependency version here as well.
2. Update `packages/pdfrx/CHANGELOG.md` with user-facing changes.
3. Update `packages/pdfrx/README.md` with the new version.
   - Update version numbers in sample snippets.
   - Note new features or breaking changes when relevant.
   - Report any issues found in the example app or documentation to the owner.
4. Update the root `README.md` (at least, the versions hard-coded on it).
5. Run `dart pub get` to refresh dependencies.
6. Run tests:
   - `dart test` inside `packages/pdfrx_engine/`.
   - `flutter test` inside `packages/pdfrx/`.
7. Validate the example app builds: `flutter build web --wasm` in `packages/pdfrx/example/viewer`.
8. Run `pana` in `packages/pdfrx` (and other packages being released) to validate code integrity.
   - Flag any WASM compatibility warnings emitted by `pana`.
9. Commit changes with `Release pdfrx vX.Y.Z` or `Release pdfrx_engine vX.Y.Z`.
10. Tag the commit with `git tag pdfrx-vX.Y.Z` or `git tag pdfrx_engine-vX.Y.Z`.
11. Push commits and tags.
12. Publish with `flutter pub publish` inside `packages/pdfrx/`.
13. Comment on related GitHub issues/PRs once the release is live.
    - Use `gh issue comment` or `gh pr comment` as appropriate.
    - If a PR references issues, comment on those issues as well.
    - Template:

      ```md
      The FIX|UPDATE|SOMETHING for this issue has been released in v[x.y.z](https://pub.dev/packages/pdfrx/versions/x.y.z).

      ...Fix/update summary...

      Written by [AGENT SIGNATURE]
      ```

    - Focus on release notes and what changed; link to the version-specific changelog entry.

## pdfium_dart Releases

1. Update the version in `packages/pdfium_dart/pubspec.yaml`.
   - Follow semantic versioning based on the scope of changes.
2. Update `packages/pdfium_dart/CHANGELOG.md` with user-facing changes.
   - Include PDFium version updates if applicable.
   - Document any changes to the FFI bindings or `getPdfium()` functionality.
3. Update `packages/pdfium_dart/README.md` if necessary.
4. Run tests: `dart test` inside `packages/pdfium_dart/`.
5. Run `pana` inside `packages/pdfium_dart/` to validate the package.
6. Commit changes with `Release pdfium_dart vX.Y.Z`.
7. Tag the commit with `git tag pdfium_dart-vX.Y.Z`.
8. Push commits and tags.
9. Publish with `dart pub publish` inside `packages/pdfium_dart/`.

## pdfium_flutter Releases

1. Update the version in `packages/pdfium_flutter/pubspec.yaml`.
   - If `pdfium_dart` was updated, update the dependency version here as well.
2. Update `packages/pdfium_flutter/CHANGELOG.md` with user-facing changes.
   - Include PDFium binary version updates if applicable.
   - Document platform-specific changes (iOS, Android, Windows, macOS, Linux).
3. Update `packages/pdfium_flutter/README.md` if necessary.
4. Update platform-specific build configurations if PDFium binaries changed:
   - `darwin/pdfium_flutter.podspec` for iOS/macOS (CocoaPods)
   - `darwin/pdfium_flutter/Package.swift` for Swift Package Manager
   - `android/CMakeLists.txt` for Android
   - `windows/CMakeLists.txt` for Windows
   - `linux/CMakeLists.txt` for Linux
5. Run tests: `flutter test` inside `packages/pdfium_flutter/`.
6. Run `pana` inside `packages/pdfium_flutter/` to validate the package.
7. Commit changes with `Release pdfium_flutter vX.Y.Z`.
8. Tag the commit with `git tag pdfium_flutter-vX.Y.Z`.
9. Push commits and tags.
10. Publish with `flutter pub publish` inside `packages/pdfium_flutter/`.

## pdfrx_coregraphics Releases

1. Update the version in `packages/pdfrx_coregraphics/pubspec.yaml`.
2. Update `packages/pdfrx_coregraphics/CHANGELOG.md` with user-facing changes.
3. Update `packages/pdfrx_coregraphics/README.md` if necessary.
4. Run tests on macOS/iOS devices if possible.
5. Run `pana` inside `packages/pdfrx_coregraphics/` to validate the package.
6. Commit changes with `Release pdfrx_coregraphics vX.Y.Z`.
7. Tag the commit with `git tag pdfrx_coregraphics-vX.Y.Z`.
8. Push commits and tags.
9. Publish with `flutter pub publish` inside `packages/pdfrx_coregraphics/`.

## Dependency Order

When releasing multiple packages, follow this order to respect dependencies:

1. **pdfium_dart** (no dependencies on other packages in monorepo)
2. **pdfium_flutter** (depends on pdfium_dart)
3. **pdfrx_engine** (depends on pdfium_dart)
4. **pdfrx** (depends on pdfrx_engine and pdfium_flutter)
5. **pdfrx_coregraphics** (depends on pdfrx_engine, independent of pdfium_flutter)

## General Notes

- Keep `CHANGELOG.md` entries user-focused and concise.
- Coordinate with the repository owner if any release blockers appear.
- When releasing multiple packages together, create a single commit with all version changes.
- Tag format: `<package_name>-vX.Y.Z` (e.g., `pdfium_dart-v0.1.3`, `pdfrx-v2.2.11`).
