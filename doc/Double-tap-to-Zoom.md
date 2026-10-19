
# Double-tap to Zoom

You can implement double-tap-to-zoom feature using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html) and [PdfOverlayInteractionRegion](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOverlayInteractionRegion-class.html):

```dart
viewerOverlayBuilder: (context, size, handleLinkTap) => [
  PdfOverlayInteractionRegion(
    onDoubleTap: (details) {
      controller.zoomUp(loop: true);
      return true;
    },
    // Make the region cover the whole viewer while keeping pointer events
    // available to the viewer itself.
    child: SizedBox(width: size.width, height: size.height),
  ),
  ...
],
```

If you want to use [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html) with double-tap-to-zoom enabled, place the double-tap-to-zoom code before [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html).


## Pinch and Trackpad Zoom

From pdfrx 2.7.0, [scaleGestureSensitivity](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scaleGestureSensitivity.html) controls live touch-pinch and trackpad pan/zoom gestures:

```dart
params: PdfViewerParams(
  scaleGestureSensitivity: 0.75,
  scaleInertiaMaxExcursion: 0.15,
),
```

The sensitivity must be finite and greater than zero. Its default is `1.0`; values below one give a gentler response, and larger values increase the response. A gesture ratio `r` produces a zoom ratio of `r` raised to this sensitivity, within the viewer's zoom limits.

[scaleInertiaMaxExcursion](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scaleInertiaMaxExcursion.html) limits post-release scale inertia to a fraction of the release scale. For example, `0.15` bounds it to 85-115% of that scale, subject to the normal zoom limits. The value must be between zero and one, exclusively. `null` preserves the default inertia behavior. This bound applies to the default inertia path when `scrollPhysics` is not configured; the scroll-physics path instead applies its scale-clamping behavior.

These options do not change double-tap zoom or pointer-signal zoom. Use `scaleByPointerScale` for pointer-scale events and Ctrl-wheel zoom.
