# pdfrx

[pdfrx](https://pub.dartlang.org/packages/pdfrx) is a PDF viewer implementation built on the top of [pdfium](https://pdfium.googlesource.com/pdfium/).
The plugin currently supports Android, iOS, Windows, macOS, Linux, and Web.

Please note that "Web" is not shown in [pub.dev](https://pub.dev/packages/pdfrx)'s platform list, but **IT DOES SUPPORT** Web.

- A [demo site](https://espresso3389.github.io/pdfrx/) using Flutter Web

![](https://private-user-images.githubusercontent.com/1311400/288040209-c4c44fde-2fb7-4e45-9261-5e33c0d1a0a9.gif?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTEiLCJleHAiOjE3MDE3ODAxNzIsIm5iZiI6MTcwMTc3OTg3MiwicGF0aCI6Ii8xMzExNDAwLzI4ODA0MDIwOS1jNGM0NGZkZS0yZmI3LTRlNDUtOTI2MS01ZTMzYzBkMWEwYTkuZ2lmP1gtQW16LUFsZ29yaXRobT1BV1M0LUhNQUMtU0hBMjU2JlgtQW16LUNyZWRlbnRpYWw9QUtJQUlXTkpZQVg0Q1NWRUg1M0ElMkYyMDIzMTIwNSUyRnVzLWVhc3QtMSUyRnMzJTJGYXdzNF9yZXF1ZXN0JlgtQW16LURhdGU9MjAyMzEyMDVUMTIzNzUyWiZYLUFtei1FeHBpcmVzPTMwMCZYLUFtei1TaWduYXR1cmU9ZTdlNmY1ODY5NWUwNjAzNzU3MWViZmU3ZDNkMGM4MTgxNWU4NmU3ZmU1NmRlNGZmYWZhNzZkNjQxNTQ5ZjdiZiZYLUFtei1TaWduZWRIZWFkZXJzPWhvc3QmYWN0b3JfaWQ9MCZrZXlfaWQ9MCZyZXBvX2lkPTAifQ.hU9zW_HQycBEC9N4heOQG7x9qc6IhSzJBIu3_4mZ7nA)

## Getting Started

The following fragment illustrates the easiest way to show a PDF file in assets:

```dart
class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pdfrx example'),
        ),
        body: PdfViewer.asset('assets/hello.pdf'),
      ),
    );
  }
}
```

## Installation

Add this to your package's `pubspec.yaml` file and execute `flutter pub get`:

```yaml
dependencies:
  pdfrx: ^0.4.6
```

### Web

For Web, you should add the following `<script>` block to your `index.html` just before `<script src="main.dart.js"... </script>` to load [PDF.js](https://mozilla.github.io/pdf.js/):

```html
<!-- IMPORTANT: load pdfjs files -->
<script
  src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js"
  type="text/javascript"
></script>
<script type="text/javascript">
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js";
  pdfRenderOptions = {
    // where cmaps are downloaded from
    cMapUrl: "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/cmaps/",
    // The cmaps are compressed in the case
    cMapPacked: true,
    // any other options for pdfjsLib.getDocument.
    // params: {}
  };
</script>
```

Please check [example's code](example/web/index.html) for the actual usage.

Please note that; with pdf.js 4.0 series, [they changed the way to load `pdfjsLib`](https://github.com/mozilla/pdf.js/issues/17228), it does not simply work with the current code. We need further investigation to support them.

## macOS

For macOS, Flutter app restrict its capability by enabling [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) by default. You can change the behavior by editing your app's entitlements files depending on your configuration. See [the discussion below](#deal-with-app-sandbox).

- [`macos/Runner/Release.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/Release.entitlements)
- [`macos/Runner/DebugProfile.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/DebugProfile.entitlements)

### Deal with App Sandbox

The easiest option to access files on your disk, set [`com.apple.security.app-sandbox`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_app-sandbox) to `false` on your entitlements file though it is not recommended for releasing apps because it completely disables [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox).

Another option is to use [`com.apple.security.files.user-selected.read-only`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-only) along with [file_selector_macos](https://pub.dev/packages/file_selector_macos). The option is better in security than the previous option.

Anyway, the example code for the plugin illustrates how to download and preview internet hosted PDF file. It uses
[`com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_client) along with [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager):

```xml
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
```

## Customizations

You can customize the behaviour and visual by configuring [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html).

### Horizontal Scroll View

By default, the pages are layed out vertically.
You can customize the layout logic by [PdfViewerParams.layoutPages](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutPages.html):

```dart
layoutPages: (pages, params) {
  final height =
      pages.fold(0.0, (prev, page) => max(prev, page.height)) +
          params.margin * 2;
  final pageLayouts = <Rect>[];
  double x = params.margin;
  for (var page in pages) {
    pageLayouts.add(
      Rect.fromLTWH(
        x,
        (height - page.height) / 2, // center vertically
        page.width,
        page.height,
      ),
    );
    x += page.width + params.margin;
  }
  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(x, height),
  );
},
```

### Showing Scroll Thumbs

By default, the viewer does never show any scroll bars nor scroll thumbs.
You can add scroll thumbs by using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html):

```dart
viewerOverlayBuilder: (context, size) => [
  // Add vertical scroll thumb on viewer's right side
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.right,
    thumbSize: const Size(40, 25),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.black,
      // Show page number on the thumb
      child: Center(
        child: Text(
          pageNumber.toString(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  ),
  // Add horizontal scroll thumb on viewer's bottom
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.bottom,
    thumbSize: const Size(80, 30),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.red,
    ),
  ),
],
```

### Adding Page Number on Page Bottom

If you want to add page number on each page, you can do that by [PdfViewerParams.pageOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlayBuilder.html):

```dart
pageOverlayBuilder: (context, pageRect, page) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: Text(page.pageNumber.toString(),
    style: const TextStyle(color: Colors.red)));
},
```
