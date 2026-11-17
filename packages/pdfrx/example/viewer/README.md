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
- [User guides](../../../../doc/README.md): configuration and feature examples.

For a Web/WASM build, run `flutter build web --wasm`. Native platform builds additionally need their platform SDKs and C toolchain.

## Android native-loading test

With an Android device or emulator selected, run the packaging regression test from this directory:

```console
flutter test integration_test/pdfium_android_loading_test.dart -d DEVICE_ID
```

It opens `assets/hello.pdf` and renders its first page, exercising the packaged PDFium library.

To run the instrumentation test on Firebase Test Lab, build the APKs from this directory:

```powershell
flutter pub get
flutter build apk --debug
cd android
.\gradlew.bat app:assembleAndroidTest
$target = (Resolve-Path '..\integration_test\pdfium_android_loading_test.dart').Path
.\gradlew.bat "-Ptarget=$target" app:assembleDebug
cd ..
```

Set the Firebase project with `gcloud config set project YOUR_FIREBASE_PROJECT_ID`. Review the device and Android version in `firebase_test_lab_issue_645.yaml` against those available in your project, then run:

```powershell
gcloud firebase test android run --flags-file=firebase_test_lab_issue_645.yaml
```
