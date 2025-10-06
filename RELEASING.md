# Releasing pdfrx and pdfrx_engine

This guide covers the full release checklist for both packages in the monorepo. Follow the steps that apply to the package you are releasing.

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

## General Notes

- Keep `CHANGELOG.md` entries user-focused and concise.
- Coordinate with the repository owner if any release blockers appear.
