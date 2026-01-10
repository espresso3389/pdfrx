# Release Process

## Important Rules for Agents

- **Never bump versions or changelog entries preemptively** - only when explicitly releasing
- Surface blockers or uncertainties to the user before continuing a release flow
- `CHANGELOG.md` should be updated only when releasing a new version
- Skip CI/CD updates and meta-doc changes (`CLAUDE.md`, `AGENTS.md`, and `doc/agents/*md`) in changelogs unless significant

## Release Order

Packages must be published in dependency order:

1. **pdfium_dart** (if changed)
2. **pdfium_flutter** (depends on pdfium_dart)
3. **pdfrx_engine** (depends on pdfium_dart)
4. **pdfrx_coregraphics** (depends on pdfrx_engine)
5. **pdfrx** (depends on pdfrx_engine, pdfium_flutter)

## Versioning

Follow semantic versioning:

- **Patch** (`X.Y.Z -> X.Y.Z+1`): Bug fixes, non-breaking changes
- **Minor** (`X.Y.Z -> X.Y+1.0`): New features, breaking changes
- **Major** (`X.Y.Z -> X+1.0.0`): Major breaking changes

## Pre-Release Checklist

For each package being released:

1. Update `CHANGELOG.md` with user-facing changes
2. Update version in `pubspec.yaml`
3. Update dependency versions in dependent packages
4. Update version references in `README.md` examples
5. Update the root `README.md` if necessary
6. Run dry-run: `dart pub publish --dry-run` or `flutter pub publish --dry-run`
7. Run `pana` to validate package quality

### pdfrx-Specific Steps

- Run tests: `dart test` in `packages/pdfrx_engine/` and `flutter test` in `packages/pdfrx/`
- Validate example app: `flutter build web --wasm` in `packages/pdfrx/example/viewer`
- Flag any WASM compatibility warnings from `pana`

### pdfium_flutter-Specific Steps

Update platform-specific build configurations if PDFium binaries changed:

- `darwin/pdfium_flutter.podspec` for iOS/macOS (CocoaPods)
- `darwin/pdfium_flutter/Package.swift` for Swift Package Manager
- `android/CMakeLists.txt` for Android
- `windows/CMakeLists.txt` for Windows
- `linux/CMakeLists.txt` for Linux

## Publishing

### Windows (Claude Code)

On Windows, use PowerShell wrapper for reliable path handling:

```bash
# For Dart packages
pwsh.exe -Command "cd 'd:\pdfrx\packages\<package>'; dart pub publish --force"

# For Flutter packages
pwsh.exe -Command "cd 'd:\pdfrx\packages\<package>'; flutter pub publish --force"
```

### Other Platforms

```bash
# For Dart packages
cd packages/<package>
dart pub publish --force

# For Flutter packages
cd packages/<package>
flutter pub publish --force
```

## Post-Release

### Commit Changes

Before tagging, commit all release changes:

```bash
git add -A
git commit -m "Release pdfrx 2.2.19, pdfrx_engine 0.3.7, etc."
git push
```

### Git Tagging

After publishing, create git tags for each released package and push them:

```bash
# Tag format: <package>-v<version>
git tag pdfium_dart-v0.1.3
git tag pdfium_flutter-v0.1.8
git tag pdfrx_engine-v0.3.7
git tag pdfrx-v2.2.19
git tag pdfrx_coregraphics-v0.1.11

# Push all tags
git push --tags
```

### Notify Issues

Comment on related GitHub issues/PRs once the release is live:

```md
The FIX|UPDATE|SOMETHING for this issue has been released in v[x.y.z](https://pub.dev/packages/pdfrx/versions/x.y.z).

...Fix/update summary...

Written by [AGENT SIGNATURE]
```

Use `gh issue comment` or `gh pr comment` as appropriate.

## Changelog Guidelines

Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) principles:

- Focus on user-facing changes, new features, bug fixes, and breaking changes
- Do NOT include implementation details
- Link to issues/PRs: `[#NNN](https://github.com/espresso3389/pdfrx/issues/NNN)`
- Use bullet points for changes

## Dependency Version Policy

### pdfrx_engine

Follows standard Dart package versioning practices.

### pdfrx

Intentionally does NOT specify version constraints for core Flutter-managed packages (collection, ffi, http, path, rxdart). This allows:

- Flutter SDK to manage dependencies based on user's Flutter version
- Broader compatibility across different Flutter stable versions
- Avoiding version conflicts for users on older Flutter stable releases

Warnings about missing version constraints during `flutter pub publish` can be safely ignored.
