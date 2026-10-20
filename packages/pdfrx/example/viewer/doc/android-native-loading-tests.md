# Android Native PDFium Loading Tests

This example includes `integration_test/pdfium_android_loading_test.dart` to check that a packaged Android app can load PDFium. It originated from [#645](https://github.com/espresso3389/pdfrx/issues/645) and remains useful as a native-packaging regression check. The test opens
`assets/hello.pdf` and renders the first page, which forces Android to load
`libpdfium.so` from the app APK.

## Run on a Local Device

From `packages/pdfrx/example/viewer`, with an Android device or emulator selected:

```console
flutter test integration_test/pdfium_android_loading_test.dart -d DEVICE_ID
```

## Build

From `packages/pdfrx/example/viewer`:

```powershell
flutter pub get
flutter build apk --debug
cd android
.\gradlew.bat app:assembleAndroidTest
$target = (Resolve-Path '..\integration_test\pdfium_android_loading_test.dart').Path
.\gradlew.bat "-Ptarget=$target" app:assembleDebug
cd ..
```

## Run on Firebase Test Lab

Set your Firebase project first:

```powershell
gcloud config set project YOUR_FIREBASE_PROJECT_ID
```

The checked-in flags file uses an example device configuration. Select a device and Android version available in your Firebase Test Lab project before running. The filename is retained for compatibility with existing invocations.

Then run:

```powershell
gcloud firebase test android run --flags-file=firebase_test_lab_issue_645.yaml
```

The expected result is a passing instrumentation test. A failure containing
`Failed to load PDFium module` means Android could not load PDFium at runtime,
even if the APK contains `libpdfium.so`.
