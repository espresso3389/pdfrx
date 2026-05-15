# Code Style and Documentation

## Code Style

- Single quotes for strings
- 120 character line width
- Relative imports within `lib/`
- Follow flutter_lints with custom rules in `analysis_options.yaml`

## Formatting

```bash
dart format .
```

Use `dart format` for both Dart and Flutter packages.

## Documentation Guidelines

### General Principles

- Use proper grammar and spelling
- Use clear and concise language
- Use consistent terminology
- Use proper headings for sections
- Use code blocks for code snippets
- Use bullet points for lists
- Use backticks (`` ` ``) for code references and file/directory/path names

### Dart Comments

- Use `///` (dartdoc comments) for public API comments
- Use reference links for classes, enums, and functions in documentation
- Even important private APIs should have dartdoc comments

### Markdown Files

- Include links to issues/PRs when relevant
  - Format: `[#NNN](https://github.com/espresso3389/pdfrx/issues/NNN)`
- Use links to pub.dev API references for public APIs mentioned in Markdown files:
  - `pdfrx`: `https://pub.dev/documentation/pdfrx/latest/pdfrx/...`
  - `pdfrx_engine`: `https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/...`
- `README.md` should provide an overview of the project, how to use it, and important notes

### Changelog

- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) principles
- Focus on user-facing changes, new features, bug fixes, and breaking changes
- Do NOT include implementation details
- Use sections for different versions
- Use bullet points for changes
- Update only when releasing a new version
