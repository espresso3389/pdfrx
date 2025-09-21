import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../pdfrx.dart';
import 'utils/platform.dart';

bool _isInitialized = false;

/// Explicitly initializes the Pdfrx library for Flutter.
///
/// This function actually sets up the following functions:
/// - [Pdfrx.loadAsset]: Loads an asset by name and returns its byte data.
/// - [Pdfrx.getCacheDirectory]: Returns the path to the temporary directory for caching.
///
/// For Dart (non-Flutter) programs, you should call [pdfrxInitialize] instead.
///
/// The function shows PDFium WASM module warnings in debug mode by default.
/// You can disable these warnings by setting [dismissPdfiumWasmWarnings] to true.
void pdfrxFlutterInitialize({bool dismissPdfiumWasmWarnings = false}) {
  if (_isInitialized) return;

  if (pdfrxEntryFunctionsOverride != null) {
    PdfrxEntryFunctions.instance = pdfrxEntryFunctionsOverride!;
  }

  Pdfrx.loadAsset ??= (name) async {
    final asset = await rootBundle.load(name);
    return asset.buffer.asUint8List();
  };
  Pdfrx.getCacheDirectory ??= getCacheDirectory;

  platformInitialize();

  // Checking pdfium.wasm availability for Web and debug builds.
  if (kDebugMode && !dismissPdfiumWasmWarnings) {
    () async {
      try {
        await Pdfrx.loadAsset!('packages/pdfrx/assets/pdfium.wasm');
        if (!kIsWeb) {
          debugPrint(
            '⚠️\u001b[37;41;1mDEBUG TIME WARNING: The app is bundling PDFium WASM module (about 4MB) as a part of the app.\u001b[0m\n'
            '\u001b[91mFor production use (not for Web/Debug), you\'d better remove the PDFium WASM module.\u001b[0m\n'
            '\u001b[91mSee https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx#note-for-building-release-builds for more details.\u001b[0m\n',
          );
        }
      } catch (e) {
        if (kIsWeb) {
          debugPrint(
            '⚠️\u001b[37;41;1mDEBUG TIME WARNING: The app is running on Web, but the PDFium WASM module is not bundled with the app.\u001b[0m\n'
            '\u001b[91mMake sure to include the PDFium WASM module in your web project.\u001b[0m\n'
            '\u001b[91mIf you explicitly set Pdfrx.pdfiumWasmModulesUrl, you can ignore this warning.\u001b[0m\n'
            '\u001b[91mSee https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx#note-for-building-release-builds for more details.\u001b[0m\n',
          );
        }
      }
    }();
  }

  /// NOTE: it's actually async, but hopefully, it finishes quickly...
  PdfrxEntryFunctions.instance.initPdfium();

  _isInitialized = true;
}

extension PdfPageExt on PdfPage {
  /// PDF page size in points (size in pixels at 72 dpi) (rotated).
  Size get size => Size(width, height);
}

extension PdfImageExt on PdfImage {
  /// Create [Image] from the rendered image.
  ///
  /// The returned [Image] must be disposed of when no longer needed.
  Future<Image> createImage() {
    final comp = Completer<Image>();
    decodeImageFromPixels(pixels, width, height, PixelFormat.bgra8888, (image) => comp.complete(image));
    return comp.future;
  }
}

extension PdfRectExt on PdfRect {
  /// Convert to [Rect] in Flutter coordinate.
  /// [page] is the page to convert the rectangle.
  /// [scaledPageSize] is the scaled page size to scale the rectangle. If not specified, [PdfPage].size is used.
  /// [rotation] is the rotation of the page. If not specified, [PdfPage.rotation] is used.
  Rect toRect({required PdfPage page, Size? scaledPageSize, int? rotation}) {
    final rotated = rotate(rotation ?? page.rotation.index, page);
    final scale = scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return Rect.fromLTRB(
      rotated.left * scale,
      (page.height - rotated.top) * scale,
      rotated.right * scale,
      (page.height - rotated.bottom) * scale,
    );
  }

  ///  Convert to [Rect] in Flutter coordinate using [pageRect] as the page's bounding rectangle.
  Rect toRectInDocument({required PdfPage page, required Rect pageRect}) =>
      toRect(page: page, scaledPageSize: pageRect.size).translate(pageRect.left, pageRect.top);
}

extension RectPdfRectExt on Rect {
  /// Convert to [PdfRect] in PDF page coordinates.
  PdfRect toPdfRect({required PdfPage page, Size? scaledPageSize, int? rotation}) {
    final scale = scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return PdfRect(
      left / scale,
      page.height - top / scale,
      right / scale,
      page.height - bottom / scale,
    ).rotateReverse(rotation ?? page.rotation.index, page);
  }
}

extension PdfPointExt on PdfPoint {
  /// Convert to [Offset] in Flutter coordinate.
  /// [page] is the page to convert the rectangle.
  /// [scaledPageSize] is the scaled page size to scale the rectangle. If not specified, [PdfPage].size is used.
  /// [rotation] is the rotation of the page. If not specified, [PdfPage.rotation] is used.
  Offset toOffset({required PdfPage page, Size? scaledPageSize, int? rotation}) {
    final rotated = rotate(rotation ?? page.rotation.index, page);
    final scale = scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return Offset(rotated.x * scale, (page.height - rotated.y) * scale);
  }

  Offset toOffsetInDocument({required PdfPage page, required Rect pageRect}) {
    final rotated = rotate(page.rotation.index, page);
    final scale = pageRect.height / page.height;
    return Offset(rotated.x * scale, (page.height - rotated.y) * scale).translate(pageRect.left, pageRect.top);
  }
}

extension OffsetPdfPointExt on Offset {
  /// Convert to [PdfPoint] in PDF page coordinates.
  PdfPoint toPdfPoint({required PdfPage page, Size? scaledPageSize, int? rotation}) {
    final scale = scaledPageSize == null ? 1.0 : page.height / scaledPageSize.height;
    return PdfPoint(dx * scale, page.height - dy * scale).rotateReverse(rotation ?? page.rotation.index, page);
  }
}
