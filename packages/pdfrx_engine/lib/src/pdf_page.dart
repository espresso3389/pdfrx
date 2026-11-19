import 'dart:async';

import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'pdf_document.dart';
import 'pdf_document_event.dart';
import 'pdf_image.dart';
import 'pdf_link.dart';
import 'pdf_page_proxies.dart';
import 'pdf_page_status_change.dart';
import 'pdf_text.dart';
import 'pdf_text_formatter.dart';

/// Handles a PDF page in [PdfDocument].
///
/// See [PdfDocument.pages].
abstract class PdfPage {
  /// PDF document.
  PdfDocument get document;

  /// Page number. The first page is 1.
  int get pageNumber;

  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  double get width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  double get height;

  /// PDF page rotation.
  PdfPageRotation get rotation;

  /// Whether the page is really loaded or not.
  ///
  /// If the value is false, the page's [width], [height], and [rotation] are just guessed values and
  /// will be updated when the page is really loaded (progressive loading case only).
  ///
  /// If you want to wait until the page is really loaded, use [PdfPageBaseExtensions.ensureLoaded] or
  /// [PdfPageBaseExtensions.waitForLoaded].
  bool get isLoaded;

  /// Render a sub-area or full image of specified PDF file.
  /// Returned image should be disposed after use.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels.
  /// - If [x], [y] are not specified, (0,0) is used.
  /// - If [width], [height] are not specified, [fullWidth], [fullHeight] are used.
  /// - If [fullWidth], [fullHeight] are not specified, [PdfPage.width] and [PdfPage.height] are used (it means rendered at 72-dpi).
  /// [backgroundColor] is `AARRGGBB` integer color notation used to fill the background of the page. If no color is specified, 0xffffffff (white) is used.
  /// - [annotationRenderingMode] controls to render annotations or not. The default is [PdfAnnotationRenderingMode.annotationAndForms].
  /// - [flags] is used to specify additional rendering flags. The default is [PdfPageRenderFlags.none].
  /// - [cancellationToken] can be used to cancel the rendering process. It must be created by [createCancellationToken].
  /// - [priority] controls scheduling on backends that support it. When omitted, rendering is high priority, or low
  ///   priority inside `Pdfrx.runAsBackgroundWork`. It does not change image quality.
  ///
  /// If the page is not loaded yet (progressive loading case only), its dimensions and rotation may be estimates.
  /// Rendering behavior for an unloaded page depends on the backend.
  ///
  /// The following code extract the area of (20,30)-(120,130) from the page image rendered at 1000x1500 pixels:
  /// ```dart
  /// final image = await page.render(
  ///   x: 20,
  ///   y: 30,
  ///   width: 100,
  ///   height: 100,
  ///   fullWidth: 1000,
  ///   fullHeight: 1500,
  /// );
  /// ```
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  });

  /// Create [PdfPageRenderCancellationToken] to cancel the rendering process.
  PdfPageRenderCancellationToken createCancellationToken();

  /// Load plain text for the page.
  ///
  /// For text with character bounding boxes, use [PdfPageBaseExtensions.loadStructuredText].
  ///
  /// If the page is not loaded yet (progressive loading case only), this function returns null.
  Future<PdfPageRawText?> loadText();

  /// Load links.
  ///
  /// Results may be cached for this page instance. Reload the page after modifying its annotations.
  ///
  /// If [compact] is true, the link data may be compacted. Cached implementations may return compact data for both
  /// values to avoid retaining duplicate results. See [PdfLink.compact] for more info.
  ///
  /// If [enableAutoLinkDetection] is true, the function tries to detect Web links automatically.
  /// This is useful if the PDF file contains text that looks like Web links but not defined as links in the PDF.
  /// The default is true.
  ///
  /// If the page is not loaded yet (progressive loading case only), this function returns an empty list.
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true});
}

/// Caches [loadLinksUncached] in a bounded cache shared by a document's pages.
///
/// Cached links are compacted with [PdfLink.compact], made unmodifiable, and shared by raw and compact requests.
/// The cache retains at most 32 page/mode entries and 1 MiB of estimated Dart data, evicting least recently used
/// entries. Both auto-detection modes count toward these limits. A result larger than the byte limit is returned
/// without caching it. In-flight extractions and results retained by callers are outside this cache budget.
/// Failures are not cached. Page status changes and document disposal invalidate the affected entries.
mixin PdfPageLinkCache on PdfPage {
  static final _documentCaches = Expando<_DocumentLinkCache>();

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) {
    if (!isLoaded) return Future.value(const <PdfLink>[]);
    final cache = _documentCaches[document] ??= _DocumentLinkCache(document);
    return cache.load(this, enableAutoLinkDetection);
  }

  /// Loads links for one auto-detection mode without using the page cache.
  @protected
  Future<List<PdfLink>> loadLinksUncached(bool enableAutoLinkDetection);
}

class _DocumentLinkCache {
  _DocumentLinkCache(PdfDocument document) {
    var pageCount = document.pages.length;
    document.events.listen(
      (event) {
        if (event is PdfDocumentPageStatusChangedEvent) {
          final newPageCount = event.document.pages.length;
          if (newPageCount < pageCount) {
            // Removed pages need not appear in changes. Clear the small cache rather than scan all page proxies.
            _clear();
          }
          pageCount = newPageCount;
          final changed = event.changes;
          for (final key in _entries.keys.where((key) => changed.containsKey(key.page.pageNumber)).toList()) {
            _remove(key);
          }
          _pending.removeWhere((key, _) => changed.containsKey(key.page.pageNumber));
        }
      },
      onDone: () {
        _closed = true;
        _clear();
      },
    );
    // Native and Web documents replay prior events. Drain those before starting this cache's first extraction.
    _initialEvents = Future<void>.delayed(Duration.zero).then((_) {
      _initialEvents = null;
    });
  }

  static const _maximumEntries = 32;
  static const _maximumBytes = 1024 * 1024;
  final _entries = <_PageLinkKey, ({List<PdfLink> links, int bytes})>{};
  final _pending = <_PageLinkKey, Future<List<PdfLink>>>{};
  int _estimatedBytes = 0;
  bool _closed = false;
  Future<void>? _initialEvents;

  Future<List<PdfLink>> load(PdfPageLinkCache page, bool enableAutoLinkDetection) {
    final initialEvents = _initialEvents;
    if (initialEvents != null) return initialEvents.then((_) => load(page, enableAutoLinkDetection));
    if (_closed) return Future.error(StateError('Cannot load links from a closed document.'));
    final key = _PageLinkKey(page, enableAutoLinkDetection);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future.value(cached.links);
    }
    final pending = _pending[key];
    if (pending != null) return pending;

    late final Future<List<PdfLink>> loading;
    loading = Future<List<PdfLink>>.sync(() => page.loadLinksUncached(enableAutoLinkDetection))
        .then((loaded) => List<PdfLink>.unmodifiable([for (final link in loaded) link.compact()]))
        .then(
          (links) {
            if (!_closed && identical(_pending[key], loading)) {
              _pending.remove(key);
              final bytes = _estimateBytes(links);
              if (bytes <= _maximumBytes) {
                _entries[key] = (links: links, bytes: bytes);
                _estimatedBytes += bytes;
                while (_entries.length > _maximumEntries || _estimatedBytes > _maximumBytes) {
                  _remove(_entries.keys.first);
                }
              }
            }
            return links;
          },
          onError: (Object error, StackTrace stack) {
            if (identical(_pending[key], loading)) _pending.remove(key);
            Error.throwWithStackTrace(error, stack);
          },
        );
    return _pending[key] = loading;
  }

  void _clear() {
    _entries.clear();
    _pending.clear();
    _estimatedBytes = 0;
  }

  void _remove(_PageLinkKey key) {
    final removed = _entries.remove(key);
    if (removed != null) _estimatedBytes -= removed.bytes;
  }

  /// Includes link geometry, destinations, URLs, and annotation strings; not a heap/RSS measurement.
  static int _estimateBytes(List<PdfLink> links) =>
      64 +
      links.fold<int>(0, (size, link) {
        final annotation = link.annotation;
        return size +
            192 +
            link.rects.length * 64 +
            (link.url?.toString().length ?? 0) * 2 +
            (link.dest?.params?.length ?? 0) * 16 +
            ((annotation?.title?.length ?? 0) +
                    (annotation?.subject?.length ?? 0) +
                    (annotation?.content?.length ?? 0)) *
                2;
      });
}

/// Uses page identity, including when a backend implements value equality for its pages.
class _PageLinkKey {
  const _PageLinkKey(this.page, this.enableAutoLinkDetection);

  final PdfPage page;
  final bool enableAutoLinkDetection;

  @override
  bool operator ==(Object other) =>
      other is _PageLinkKey && identical(page, other.page) && enableAutoLinkDetection == other.enableAutoLinkDetection;

  @override
  int get hashCode => Object.hash(identityHashCode(page), enableAutoLinkDetection);
}

/// Extension methods for [PdfPage].
extension PdfPageBaseExtensions on PdfPage {
  /// Load structured text with character bounding boxes.
  ///
  /// The function internally does test flow analysis (reading order) and line segmentation to detect
  /// text direction and line breaks.
  ///
  /// To access the raw text, use [loadText].
  ///
  /// Returns empty text for an unloaded page unless [ensureLoaded] is true, in which case it waits for loading.
  Future<PdfPageText> loadStructuredText({bool ensureLoaded = false}) async {
    final page = ensureLoaded && !isLoaded ? await this.ensureLoaded() : this;
    return PdfTextFormatter.loadStructuredText(page, pageNumberOverride: pageNumber);
  }

  /// Stream of page status change events for this page.
  ///
  /// The event is based on the page position (page number), so the page instance identity may change if the page is
  /// replaced by another instance with the same page number.
  Stream<PdfPageStatusChange> get events {
    return document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent && event.changes.containsKey(pageNumber))
        .map((event) => (event as PdfDocumentPageStatusChangedEvent).changes[pageNumber]!);
  }

  /// Stream of latest page instances when the page status changes.
  ///
  /// The page instance identity may change if the page is replaced by another instance with the same page number.
  /// For example, when the page is loaded, the instance may be replaced with a fully loaded page instance.
  /// This stream emits the latest instance of the page whenever a status change event occurs for this page.
  /// Note that this stream may emit the same instance multiple times if the page is not replaced.
  Stream<PdfPage> get latestPageStream =>
      Stream.value(this).concatWith([events.map((event) => document.pages[pageNumber - 1])]);

  /// Ensure the page is really loaded.
  ///
  /// Returns the latest instance of the page once it is loaded.
  ///
  /// If you want to specify a timeout, use [waitForLoaded] instead.
  Future<PdfPage> ensureLoaded() async {
    return await waitForLoaded() ?? (throw StateError('Document closed before page $pageNumber was loaded.'));
  }

  /// Wait until the page is really loaded.
  ///
  /// Returns the latest instance of the page once it is loaded.
  /// Returns null on [timeout], [cancelLoading], or document closure.
  Future<PdfPage?> waitForLoaded({Duration? timeout, Future<void>? cancelLoading}) async {
    final newPage = document.pages[pageNumber - 1];
    if (newPage.isLoaded) {
      return newPage;
    }
    final completer = Completer<PdfPage?>();
    void complete(PdfPage? page) {
      if (!completer.isCompleted) completer.complete(page);
    }

    void completeError(Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }

    final subscription = events.listen(
      (event) {
        if (event.page.isLoaded) complete(event.page);
      },
      onDone: () => complete(null),
      onError: completeError,
    );
    final timer = timeout == null ? null : Timer(timeout, () => complete(null));
    cancelLoading?.then((_) => complete(null), onError: completeError);
    try {
      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }
}

/// Extension to add rotation capability to [PdfPage].
///
/// Use these functions to create rotated pages when reorganizing or combining PDFs.
///
/// The following example shows how to fix page orientations:
///
/// ```dart
/// final doc = await PdfDocument.openFile('document.pdf');
/// doc.pages = [
///   doc.pages[0],
///   doc.pages[1].rotatedTo(PdfPageRotation.clockwise90),
///   doc.pages[2].rotatedBy(PdfPageRotation.clockwise90),
///   doc.pages[3].rotatedCW90(),
/// ];
/// await File('fixed.pdf').writeAsBytes(await doc.encodePdf());
/// ```
extension PdfPageWithRotationExtension on PdfPage {
  /// Rotates a page with the specified rotation.
  ///
  /// The method returns a new page with rotation equal to [rotation].
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedTo(PdfPageRotation rotation) {
    if (rotation == this.rotation) {
      return this; // No rotation change needed
    }
    return PdfPageRotated(this, rotation);
  }

  /// Rotates a page with rotation added to the current rotation.
  ///
  /// The method returns a new page with rotation equal to (current rotation + [delta]).
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedBy(PdfPageRotation delta) {
    final newRotation = PdfPageRotation.values[(rotation.index + delta.index) & 3];
    return rotatedTo(newRotation);
  }

  /// Rotates a page clockwise by 90 degrees.
  ///
  /// This method returns a new page with rotation equal to (current rotation + clockwise90).
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedCW90() => rotatedBy(PdfPageRotation.clockwise90);

  /// Rotates a page counter-clockwise by 90 degrees.
  ///
  /// This method returns a new page with rotation equal to (current rotation + clockwise270).
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedCCW90() => rotatedBy(PdfPageRotation.clockwise270);

  /// Rotates a page clockwise by 180 degrees.
  ///
  /// This method returns a new page with rotation equal to (current rotation + clockwise180).
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotated180() => rotatedBy(PdfPageRotation.clockwise180);
}

/// Extension to add page renumbering capability to [PdfPage].
///
/// This is used internally when assembling documents, but can also be used manually.
extension PdfPageRenumberedExtension on PdfPage {
  /// Renumbers a page with the specified page number.
  ///
  /// See usage example in [PdfPageRenumberedExtension].
  PdfPage withPageNumber(int pageNumber) {
    if (pageNumber == this.pageNumber) {
      return this; // No page number change needed
    }
    return PdfPageRenumbered(this, pageNumber: pageNumber);
  }
}

/// Page rotation.
enum PdfPageRotation { none, clockwise90, clockwise180, clockwise270 }

extension PdfPageRotationEnumExtension on PdfPageRotation {
  /// Get counter-clockwise 90 degree rotation value from the current rotation.
  PdfPageRotation get rotateCCW90 => PdfPageRotation.values[(index + 3) % 4];

  /// Get clockwise 90 degree rotation value from the current rotation.
  PdfPageRotation get rotateCW90 => PdfPageRotation.values[(index + 1) % 4];

  /// Get 180 degree rotation value from the current rotation.
  PdfPageRotation get rotate180 => PdfPageRotation.values[(index + 2) % 4];

  /// Add two rotations.
  PdfPageRotation operator +(PdfPageRotation other) => PdfPageRotation.values[(index + other.index) % 4];
}

/// Annotation rendering mode.
enum PdfAnnotationRenderingMode {
  /// Do not render annotations.
  none,

  /// Render annotations.
  annotation,

  /// Render annotations and forms.
  annotationAndForms,
}

/// Flags for [PdfPage.render].
///
/// Basically, they are PDFium's `FPDF_RENDER_*` flags and not supported on PDF.js.
abstract class PdfPageRenderFlags {
  /// None.
  static const none = 0;

  /// `FPDF_LCD_TEXT` flag.
  static const lcdText = 0x0002;

  /// `FPDF_GRAYSCALE` flag.
  static const grayscale = 0x0008;

  /// `FPDF_RENDER_LIMITEDIMAGECACHE` flag.
  static const limitedImageCache = 0x0200;

  /// `FPDF_RENDER_FORCEHALFTONE` flag.
  static const forceHalftone = 0x0400;

  /// `FPDF_PRINTING` flag.
  static const printing = 0x0800;

  /// `FPDF_RENDER_NO_SMOOTHTEXT` flag.
  static const noSmoothText = 0x1000;

  /// `FPDF_RENDER_NO_SMOOTHIMAGE` flag.
  static const noSmoothImage = 0x2000;

  /// `FPDF_RENDER_NO_SMOOTHPATH` flag.
  static const noSmoothPath = 0x4000;

  /// Output image is in premultiplied alpha format.
  static const premultipliedAlpha = 0x80000000;
}

/// Token to try to cancel the rendering process.
abstract class PdfPageRenderCancellationToken {
  /// Cancel the rendering process.
  void cancel();

  /// Determine whether the rendering process is canceled or not.
  bool get isCanceled;
}

/// Scheduling priority for page rendering. Backends may treat this as a hint.
enum PdfPageRenderPriority {
  /// Content the user is waiting to see.
  high,

  /// Work that can wait for visible content.
  normal,

  /// Speculative work such as prefetching and thumbnails.
  low,
}
