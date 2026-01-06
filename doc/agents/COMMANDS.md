# Commands Reference

## Environment Notes

- This project uses a **pub workspace**. Running `dart pub get` in any directory fetches dependencies for all packages.
- Prefer `rg`/`rg --files` for search and discovery tasks; they are significantly faster than alternatives.

## Windows-Specific Notes (Claude Code)

When running on Windows, Claude Code's Bash tool runs in a POSIX-like shell environment. Be aware of these issues:

### Path Handling

- **Use forward slashes** or properly escaped backslashes in paths
- **Windows paths like `d:\pdfrx`** may not work directly; wrap commands with `pwsh.exe -Command "..."`
- When using `cd`, the path may fail silently; prefer running commands with full paths or use PowerShell

### Command Execution

```bash
# WRONG - may fail with path issues
cd d:\pdfrx\packages\pdfrx && flutter pub get

# CORRECT - use PowerShell wrapper
pwsh.exe -Command "cd 'd:\pdfrx\packages\pdfrx'; flutter pub get"
```

### Git Commands

```bash
# WRONG - cd may not work as expected
cd d:\pdfrx && git status

# CORRECT - use -C flag for git
git -C "d:\pdfrx" status
git -C "d:\pdfrx" log --oneline -10

# Or use PowerShell
pwsh.exe -Command "cd 'd:\pdfrx'; git status"
```

### Publishing Packages

```bash
# Use PowerShell for pub publish
pwsh.exe -Command "cd 'd:\pdfrx\packages\pdfrx'; flutter pub publish --force"
pwsh.exe -Command "cd 'd:\pdfrx\packages\pdfrx_engine'; dart pub publish --force"
```

### GitHub CLI (gh)

```bash
# gh commands work directly but use proper quoting
gh issue comment 123 --repo espresso3389/pdfrx --body "Comment text here"
```

## Common Commands

### Flutter Plugin (packages/pdfrx)

```bash
cd packages/pdfrx
flutter pub get
flutter analyze
flutter test
flutter format .
```

### Core Engine (packages/pdfrx_engine)

```bash
cd packages/pdfrx_engine
dart pub get
dart analyze
dart test
dart format .
```

## Platform Builds

```bash
cd packages/pdfrx/example/viewer
flutter run
flutter build appbundle    # Android
flutter build ios          # iOS
flutter build web --wasm   # Web
flutter build linux        # Linux
flutter build windows      # Windows
flutter build macos        # macOS
```

## FFI Bindings

FFI bindings for PDFium are maintained in the `pdfium_dart` package and generated using `ffigen`.

### Prerequisites

The `ffigen` process requires LLVM/Clang:

- **macOS**: `brew install llvm`
- **Linux (Ubuntu/Debian)**: `apt-get install libclang-dev`
- **Linux (Fedora)**: `dnf install clang-devel`
- **Windows**: Install LLVM from [llvm.org](https://releases.llvm.org/)

### Generating Bindings

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

### On-Demand PDFium Downloads

The `pdfium_dart` package provides a `getPdfium()` function that downloads PDFium binaries on demand. Useful for testing or CLI applications.

## Testing

Tests download PDFium binaries automatically for supported platforms.

```bash
# Test pdfrx_engine
cd packages/pdfrx_engine
dart test

# Test pdfrx Flutter plugin
cd packages/pdfrx
flutter test
```
