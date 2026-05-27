# Issue 645 Firebase Test Lab Reproduction

This example app includes a focused Android integration test for
[#645](https://github.com/espresso3389/pdfrx/issues/645). The test opens
`assets/hello.pdf` and renders the first page, which forces Android to load
`libpdfium.so` from the app APK.

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

Then run:

```powershell
gcloud firebase test android run --flags-file=firebase_test_lab_issue_645.yaml
```

The expected result is a passing instrumentation test. A failure containing
`Failed to load PDFium module` means Android could not load PDFium at runtime,
even if the APK contains `libpdfium.so`.
