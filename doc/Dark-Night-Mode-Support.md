[PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) does not have any native dark (or night) mode support but it can be easily implemented using [ColorFiltered](https://api.flutter.dev/flutter/widgets/ColorFiltered-class.html) widget:

```dart
ColorFiltered(
  colorFilter: ColorFilter.mode(Colors.white, darkMode ? BlendMode.difference : BlendMode.dst),
  child: PdfViewer.file(filePath, ...),
),
```

The trick is originally introduced by [pckimlong](https://github.com/pckimlong).