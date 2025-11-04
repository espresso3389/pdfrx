import 'pdf_document.dart';
import 'pdf_image.dart';
import 'pdf_link.dart';
import 'pdf_page.dart';
import 'pdf_text.dart';
import 'pdf_text_formatter.dart';

/// Proxy interface for [PdfPage].
///
/// Used for creating proxy pages that modify behavior of the base page.
///
/// For implementation, see [PdfPageRenumbered] and [PdfPageRotated].
abstract class PdfPageProxy implements PdfPage {
  PdfPage get basePage;
}

/// Extension to unwrap [PdfPageProxy] on [PdfPage].
extension PdfPageProxyExtension on PdfPage {
  /// Unwrap the page to get the base page of type [T].
  ///
  /// If the base page of type [T] is not found, returns null.
  T? unwrap<T extends PdfPage>() {
    final pThis = this;
    if (pThis is T) return pThis;
    if (pThis is PdfPageProxy) return pThis.basePage.unwrap();
    return null;
  }

  /// Unwrap the page until [stopCondition] is met.
  ///
  /// If the condition is met, returns null.
  PdfPage? unwrapUntil(bool Function(PdfPage page) stopCondition) {
    var current = this;
    while (true) {
      if (stopCondition(current)) return current;
      if (current is PdfPageProxy) {
        current = current.basePage;
      } else {
        return null;
      }
    }
  }
}

/// PDF page wrapper that renumbers the page number.
class PdfPageRenumbered implements PdfPageProxy {
  PdfPageRenumbered(PdfPage basePage, {required this.pageNumber})
    : basePage = basePage.unwrapUntil((p) => p is! PdfPageRenumbered)!;

  @override
  final PdfPage basePage;

  @override
  final int pageNumber;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => basePage.createCancellationToken();

  @override
  PdfDocument get document => basePage.document;

  @override
  PdfPageRotation get rotation => basePage.rotation;

  @override
  double get width => basePage.width;

  @override
  double get height => basePage.height;

  @override
  bool get isLoaded => basePage.isLoaded;

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) =>
      basePage.loadLinks(compact: compact, enableAutoLinkDetection: enableAutoLinkDetection);

  @override
  Future<PdfPageRawText?> loadText() => basePage.loadText();

  @override
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
  }) => basePage.render(
    x: x,
    y: y,
    width: width,
    height: height,
    fullWidth: fullWidth,
    fullHeight: fullHeight,
    backgroundColor: backgroundColor,
    annotationRenderingMode: annotationRenderingMode,
    flags: flags,
    cancellationToken: cancellationToken,
    rotationOverride: rotationOverride,
  );

  @override
  Future<PdfPageText> loadStructuredText() => PdfTextFormatter.loadStructuredText(this, pageNumberOverride: pageNumber);
}

/// PDF page wrapper that applies an absolute rotation to the base page.
class PdfPageRotated implements PdfPageProxy {
  PdfPageRotated(PdfPage basePage, this.rotation) : basePage = basePage.unwrapUntil((p) => p is! PdfPageRotated)!;

  @override
  final PdfPage basePage;

  // Override rotation to return the effective rotation
  @override
  final PdfPageRotation rotation;

  /// Check if dimensions need to be swapped (for 90° or 270° rotations).
  /// This is relative to the source page's rotation.
  bool get _swapWH => shouldSwapWH(rotation);

  bool shouldSwapWH(PdfPageRotation rotation) => ((rotation.index - basePage.rotation.index) & 1) == 1;

  // Delegate basic properties
  @override
  PdfDocument get document => basePage.document;

  @override
  int get pageNumber => basePage.pageNumber;

  @override
  bool get isLoaded => basePage.isLoaded;

  // Swap width/height if additional rotation is 90° or 270°
  @override
  double get width => _swapWH ? basePage.height : basePage.width;

  @override
  double get height => _swapWH ? basePage.width : basePage.height;

  // Override render to pass the effective rotation as rotationOverride
  @override
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
  }) {
    return basePage.render(
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundColor: backgroundColor,
      rotationOverride: rotationOverride ?? rotation,
      annotationRenderingMode: annotationRenderingMode,
      flags: flags,
      cancellationToken: cancellationToken,
    );
  }

  // All other methods just delegate - text/links work correctly because they use `rotation` property
  @override
  PdfPageRenderCancellationToken createCancellationToken() => basePage.createCancellationToken();

  @override
  Future<PdfPageRawText?> loadText() => basePage.loadText();

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) =>
      basePage.loadLinks(compact: compact, enableAutoLinkDetection: enableAutoLinkDetection);

  // Text methods don't depend on rotation - just delegate to source
  @override
  Future<PdfPageText> loadStructuredText() => basePage.loadStructuredText();
}
