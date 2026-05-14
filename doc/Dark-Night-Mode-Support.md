# Dark/Night Mode Support

[PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) does not have any native dark (or night) mode support but it can be easily implemented using [ColorFiltered](https://api.flutter.dev/flutter/widgets/ColorFiltered-class.html) widget:

```dart
ColorFiltered(
  colorFilter: ColorFilter.mode(Colors.white, darkMode ? BlendMode.difference : BlendMode.dst),
  child: PdfViewer.file(filePath, ...),
),
```

## Android diagonal line workaround

On some Android devices, `ColorFilter.mode` with `BlendMode.difference` may show a grey diagonal line across the screen. This is a Flutter rendering bug rather than a pdfrx rendering issue; see [pdfrx #492](https://github.com/espresso3389/pdfrx/issues/492) and [flutter/flutter #176949](https://github.com/flutter/flutter/issues/176949).

As a workaround, use an equivalent color matrix instead of `ColorFilter.mode`:

```dart
const invertColors = ColorFilter.matrix([
  -1, 0, 0, 0, 255,
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);

ColorFiltered(
  colorFilter: darkMode ? invertColors : const ColorFilter.mode(Colors.white, BlendMode.dst),
  child: PdfViewer.file(filePath, ...),
),
```

This code change is only a workaround for the Flutter bug. If Flutter fixes the underlying issue, the simpler `ColorFilter.mode` approach should be sufficient again.

The trick is originally introduced by [pckimlong](https://github.com/pckimlong).
