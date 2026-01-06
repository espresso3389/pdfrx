# AGENTS.md

This file provides guidance to AI agents and developers when working with code in this repository.

## Quick Start for Agents

- Keep existing user changes intact; if you notice unexpected edits you didn't make, pause and ask the user how to proceed.
- Prefer fast, non-destructive tools (`rg`, `rg --files`, targeted tests) and run commands with an explicit `workdir`; avoid wandering `cd` commands.
- Leave release artifacts (`CHANGELOG.md`, version numbers, tags) untouched unless the task is explicitly about publishing.
- Default to ASCII output and add only brief clarifying comments when the code is non-obvious.

## Documentation Index

Detailed guidance is split into focused files in `doc/agents/`:

- [doc/agents/PROJECT-STRUCTURE.md](doc/agents/PROJECT-STRUCTURE.md) - Package overview, dependencies, and architecture
- [doc/agents/COMMANDS.md](doc/agents/COMMANDS.md) - Common commands, testing, and platform builds
- [doc/agents/RELEASING.md](doc/agents/RELEASING.md) - Release process and publishing checklist
- [doc/agents/CODE-STYLE.md](doc/agents/CODE-STYLE.md) - Code style, documentation, and dependency policies

## Project Overview (Summary)

pdfrx is a monorepo containing five packages:

1. **pdfium_dart** - Low-level Dart FFI bindings for PDFium
2. **pdfium_flutter** - Flutter FFI plugin bundling PDFium binaries
3. **pdfrx_engine** - Platform-agnostic PDF rendering API (pure Dart)
4. **pdfrx** - Cross-platform PDF viewer Flutter plugin
5. **pdfrx_coregraphics** - CoreGraphics-backed renderer for iOS/macOS (experimental)

See [doc/agents/PROJECT-STRUCTURE.md](doc/agents/PROJECT-STRUCTURE.md) for detailed package descriptions.
