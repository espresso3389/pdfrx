# pdfrx_coregraphics

CoreGraphics-backed renderer for [pdfrx](https://pub.dev/packages/pdfrx) on iOS and macOS.

**⚠️ EXPERIMENTAL: This package is in very early experimental stage. APIs and functionality may change significantly.**

This plugin provides a [`PdfrxEntryFunctions`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions-class.html) implementation that uses PDFKit/CoreGraphics instead of the bundled PDFium
runtime. It is intended for teams that prefer the system PDF stack on Apple platforms while keeping the pdfrx widget
API.

## Requirements

- Flutter 3.50 or later (Dart 3.14 or later)
- iOS 15 or later
- macOS 12 or later

## Installation

Add the package to your Flutter app:

```yaml
dependencies:
  pdfrx: ^3.1.0
  pdfrx_coregraphics: ^0.5.3
```

Set the CoreGraphics entry functions before initializing pdfrx:

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PdfrxEntryFunctions.instance = PdfrxCoreGraphicsEntryFunctions();
  await pdfrxFlutterInitialize();
  runApp(const MyApp());
}
```

After installation, pdfrx uses the CoreGraphics backend. See the limitations below when using document and widget APIs.

## Removing PDFium Dependencies (Reducing App Size)

By default, pdfrx includes the PDFium XCFramework for iOS and macOS even when using `pdfrx_coregraphics`. If you're only using the CoreGraphics backend, you can remove these PDFium dependencies to reduce your app size.

Run this command from your project root:

```bash
flutter clean # if the environment is not clean
flutter pub get
dart run pdfrx:remove_darwin_pdfium_modules
```

This comments out the iOS and macOS ffiPlugin configurations in the resolved `pdfium_flutter` package's `pubspec.yaml`, preventing its PDFium XCFramework from being bundled with your app. The resolved package may be in the shared pub cache, so this change can also affect other projects using that cached package. Revert it when PDFium is needed again.

To revert the changes (restore PDFium dependencies):

```bash
flutter clean # if the environment is not clean
flutter pub get
dart run pdfrx:remove_darwin_pdfium_modules --revert
```

After executing it, you can run `flutter build` or `flutter run` for iOS/macOS.

## Limitations

- `compute` and `stopBackgroundWorker` are not implemented
- Incremental/custom stream loading is converted to in-memory loading
- Custom font registration is not yet supported
- In document links are always `xyz` and zoom is not reliable (or omitted) in certain situations
- Text extraction does not fully cover certain scenarios like vertical texts or R-to-L texts so far
