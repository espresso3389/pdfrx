# Visible Page Rendering State

[PdfViewerController.isReady](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/isReady.html) and [PdfViewerParams.onDocumentLoadFinished](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onDocumentLoadFinished.html) tell you that a document is loaded. They do not tell you that the pages on screen are fully rendered: [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) first paints blank placeholders or low-resolution previews and replaces them with high-resolution images as they finish rendering.

When you need to know that the visible pages are complete, for example before capturing a screenshot, generating a report, or continuing an automated test after navigating, listen to [PdfViewerController.visibleRenderState](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/visibleRenderState.html) instead of waiting for a fixed delay.

## States

[PdfVisibleRenderState](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfVisibleRenderState.html) has the following values:

| State | Meaning |
| --- | --- |
| `detached` | The controller is not attached to a viewer showing a document (loading, failed to load, or disposed). |
| `hidden` | [PdfViewerParams.isVisible](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/isVisible.html) is `false`. |
| `noVisiblePages` | No page intersects the viewport. |
| `pending` | A visible page is still being laid out, measured, or rendered, or its final image has not been painted yet. |
| `failed` | No visible page is pending, but rendering at least one of them failed. The viewer may retry and become `ready`. |
| `ready` | Every visible page has been painted with its final image for the current view. |

`ready` refers to the current document, layout, viewport size, scroll position, and zoom. Scrolling, zooming, resizing, going to another page, replacing the document, or releasing the visible pages' images (`releaseCachedImages(keepVisible: false)`) makes the state leave `ready`, and images that finish rendering for an outdated view never make it `ready`.

The "final image" is the page preview when [PdfViewerBehaviorControlParams.enableLowResolutionPagePreview](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerBehaviorControlParams/enableLowResolutionPagePreview.html) is enabled and the page is shown at or below its preview rendering scale; otherwise it is the high-resolution image of the visible part of the page. In other words, `ready` means the viewer has painted everything it will render for the current view: a page or strip too small to produce a single pixel needs no image, and a strip too thin for a high-resolution image keeps showing the preview.

`failed` is not final. The viewer retries failed pages when it repaints them, and a failure is remembered for the page and the requested image, so returning to a view whose rendering failed reports `failed` again until a retry succeeds.

## Waiting for the Visible Pages

```dart
Future<bool> waitForVisiblePages(
  PdfViewerController controller, {
  Duration timeout = const Duration(seconds: 10),
}) {
  final completer = Completer<bool>();
  void check() {
    final state = controller.visibleRenderState.value;
    if (state != PdfVisibleRenderState.ready && state != PdfVisibleRenderState.failed) return;
    controller.visibleRenderState.removeListener(check);
    completer.complete(state == PdfVisibleRenderState.ready);
  }

  controller.visibleRenderState.addListener(check);
  check();
  // The viewer may never get there, e.g. when it is hidden or disposed.
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      controller.visibleRenderState.removeListener(check);
      return false;
    },
  );
}
```

The state describes whatever is currently on screen, so an intermediate frame of an animated scroll or zoom can be `ready` if its pages happen to be rendered already. Wait for the navigation to finish before waiting for the state, for example:

```dart
await controller.goToPage(pageNumber: 5);
if (await waitForVisiblePages(controller)) {
  // The pages on screen are fully rendered.
}
```

## What the State Covers

- Only the PDF page images. Widgets from [PdfViewerParams.pageOverlaysBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlaysBuilder.html) and [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html), [PdfViewerParams.pagePaintCallbacks](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html), text selection, link highlights, and the selection magnifier are not covered; your own overlays need their own readiness checks.
- Listeners are notified outside the build, layout, and paint phases. A change detected while a frame is produced, including the paint that completes the page images, is reported after that frame has been laid out and painted, so a listener can call `setState` or capture the viewer with [RenderRepaintBoundary.toImage](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html). "Painted" means recorded into that frame's layer tree; the frame may not have reached the screen yet.
- A change applied with `setState`, such as a new document reference, is reflected once the frame that applies it has been built; read the state after that frame rather than right after calling `setState`.
- The controller keeps its listeners when the viewer is disposed and when the controller is attached to another viewer.
