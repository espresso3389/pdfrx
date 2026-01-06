# Release Process

## Important Rules for Agents

- **Never bump versions or changelog entries preemptively** - only when explicitly releasing
- Surface blockers or uncertainties to the user before continuing a release flow
- `CHANGELOG.md` should be updated only when releasing a new version

## Release Order

Packages must be published in dependency order:

1. **pdfium_dart** (if changed)
2. **pdfium_flutter** (depends on pdfium_dart)
3. **pdfrx_engine** (depends on pdfium_dart)
4. **pdfrx_coregraphics** (depends on pdfrx_engine)
5. **pdfrx** (depends on pdfrx_engine, pdfium_flutter)

## Pre-Release Checklist

For each package being released:

1. Update `CHANGELOG.md` with user-facing changes
2. Update version in `pubspec.yaml`
3. Update dependency versions in dependent packages
4. Update version references in `README.md` examples
5. Run dry-run: `dart pub publish --dry-run` or `flutter pub publish --dry-run`

## Publishing

```bash
# For Dart packages
cd packages/<package>
dart pub publish --force

# For Flutter packages
cd packages/<package>
flutter pub publish --force
```

## Post-Release

- Notify relevant GitHub issues about the fix/feature being released
- Comment format: "This has been addressed in <package> <version>. <brief description>"

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
