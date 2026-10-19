# PDF Viewer Example

This Flutter application demonstrates document opening, text search and selection, outlines, links, thumbnails, page layouts, and viewer controls.

## Run

From this directory:

```console
flutter pub get
flutter run
```

Use `flutter devices` and `flutter run -d DEVICE_ID` to select a target. The example belongs to the repository's pub workspace and uses the local packages. See the [repository requirements](../../../../README.md#requirements) before building.

## Source and Tests

- [lib/main.dart](lib/main.dart): application setup and viewer configuration.
- [lib/thumbnails_view.dart](lib/thumbnails_view.dart): shared-document thumbnails.
- [Android native-loading tests](doc/android-native-loading-tests.md): local-device and Firebase Test Lab instructions.
- [User guides](../../../../doc/README.md): configuration and feature examples.

For a Web/WASM build, run `flutter build web --wasm`. Native platform builds additionally need their platform SDKs and C toolchain.
