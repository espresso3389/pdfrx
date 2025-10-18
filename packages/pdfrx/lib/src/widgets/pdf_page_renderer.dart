import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:synchronized/extension.dart';

import '../../pdfrx.dart';

/// Delegate interface for [PdfPageRenderer].
mixin PdfPageRendererDelegate {
  /// Whether the delegate is still alive. [PdfPageRenderer] check the value to decide whether to continue
  /// rendering or not.
  ///
  /// Normally mapped to [State.mounted].
  bool isAlive();

  /// Gets the parameters for this renderer.
  PdfViewerBehaviorControlParams getBehaviorControlParams();

  /// Annotation rendering mode for page rendering.
  PdfAnnotationRenderingMode getAnnotationRenderingMode();

  /// Gets the rectangle of the specified page in the composed document coordinate space.
  Rect? getPageRect(int pageNumber);

  /// Notifies that the page image cache is updated and ready for the page.
  ///
  /// [previewUpdated] is true if the preview image is updated;
  /// false if the partial (real size) image is updated.
  void notifyPageImageUpdate(int pageNumber, bool previewUpdated);
}

/// A class to manage PDF page image rendering and caching.
class PdfPageRenderer {
  /// Creates a new instance of [PdfPageRenderer].
  PdfPageRenderer({required this.delegate});

  /// The delegate for this renderer.
  final PdfPageRendererDelegate delegate;

  /// Gets the cached preview image for the specified page.
  ///
  /// Returns null if the image is not cached. To cache the image, use [requestPreviewForPage].
  PdfImageWithScale? getPreviewImageForPage(int pageNumber) => _pageImages[pageNumber];

  /// Gets the cached partial (real size) image for the specified page.
  ///
  /// Returns null if the image is not cached. To cache the image, use [requestPartialImageForPage].
  PdfImageWithScaleAndRect? getPartialImageForPage(int pageNumber) => _pageImagesPartial[pageNumber];

  /// Requests to render and cache the preview image for the specified page at the given scale.
  Future<void> requestPreviewForPage(PdfPage page, double scale) async {
    final width = page.width * scale;
    final height = page.height * scale;
    if (width < 1 || height < 1) return;

    // if this is the first time to render the page, render it immediately
    if (!_pageImages.containsKey(page.pageNumber)) {
      _cachePagePreviewImage(page, width, height, scale);
      return;
    }

    _pageImageRenderingTimers[page.pageNumber]?.cancel();
    if (!delegate.isAlive()) return;
    _pageImageRenderingTimers[page.pageNumber] = Timer(
      delegate.getBehaviorControlParams().pageImageCachingDelay,
      () => _cachePagePreviewImage(page, width, height, scale),
    );
  }

  /// Requests to render and cache the real-size partial image for the specified page.
  ///
  /// [rect] is in the document coordinate space.
  /// [scale] is the density scale for rendering; 2.0 means 2x pixel density.
  Future<void> requestPartialImageForPage(PdfPage page, Rect rect, double scale) async {
    final pageRect = delegate.getPageRect(page.pageNumber);
    if (pageRect == null) return;
    final partRect = pageRect.intersect(rect);
    final prev = _pageImagesPartial[page.pageNumber];
    if (prev?.rect == partRect && prev?.scale == scale) return;
    if (partRect.width < 1 || partRect.height < 1) return;

    _pageImagePartialRenderingRequests[page.pageNumber]?.cancel();

    final cancellationToken = page.createCancellationToken();
    _pageImagePartialRenderingRequests[page.pageNumber] = _PdfPartialImageRenderingRequest(
      Timer(delegate.getBehaviorControlParams().partialImageLoadingDelay, () async {
        if (!delegate.isAlive() || cancellationToken.isCanceled) return;
        final newImage = await _createRealSizePartialImage(page, scale, partRect, cancellationToken);
        if (newImage != null) {
          _pageImagesPartial.remove(page.pageNumber)?.dispose();
          _pageImagesPartial[page.pageNumber] = newImage;
          delegate.notifyPageImageUpdate(page.pageNumber, false);
        }
      }),
      cancellationToken,
    );
  }

  Future<void> _cachePagePreviewImage(PdfPage page, double width, double height, double scale) async {
    if (!delegate.isAlive()) return;
    if (_pageImages[page.pageNumber]?.scale == scale) return;
    final cancellationToken = page.createCancellationToken();

    _addCancellationToken(page.pageNumber, cancellationToken);
    await synchronized(() async {
      if (!delegate.isAlive() || cancellationToken.isCanceled) return;
      if (_pageImages[page.pageNumber]?.scale == scale) return;
      PdfImage? img;
      try {
        img = await page.render(
          fullWidth: width,
          fullHeight: height,
          backgroundColor: 0xffffffff,
          annotationRenderingMode: delegate.getAnnotationRenderingMode(),
          flags: delegate.getBehaviorControlParams().limitRenderingCache
              ? PdfPageRenderFlags.limitedImageCache
              : PdfPageRenderFlags.none,
          cancellationToken: cancellationToken,
        );
        if (img == null || !delegate.isAlive() || cancellationToken.isCanceled) return;

        final newImage = PdfImageWithScale(await img.createImage(), scale);
        _pageImages[page.pageNumber]?.dispose();
        _pageImages[page.pageNumber] = newImage;
        delegate.notifyPageImageUpdate(page.pageNumber, false);
      } catch (e) {
        return; // ignore error
      } finally {
        img?.dispose();
      }
    });
  }

  Future<PdfImageWithScaleAndRect?> _createRealSizePartialImage(
    PdfPage page,
    double scale,
    Rect rect,
    PdfPageRenderCancellationToken cancellationToken,
  ) async {
    if (!delegate.isAlive() || cancellationToken.isCanceled) return null;
    final pageRect = delegate.getPageRect(page.pageNumber);
    if (pageRect == null) return null;
    final inPageRect = rect.translate(-pageRect.left, -pageRect.top);
    final x = (inPageRect.left * scale).toInt();
    final y = (inPageRect.top * scale).toInt();
    final width = (inPageRect.width * scale).toInt();
    final height = (inPageRect.height * scale).toInt();
    final fullWidth = pageRect.width * scale;
    final fullHeight = pageRect.height * scale;
    if (width < 1 || height < 1) return null;

    var flags = 0;
    if (delegate.getBehaviorControlParams().limitRenderingCache) flags |= PdfPageRenderFlags.limitedImageCache;

    PdfImage? img;
    try {
      img = await page.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xffffffff,
        annotationRenderingMode: delegate.getAnnotationRenderingMode(),
        flags: flags,
        cancellationToken: cancellationToken,
      );
      if (img == null || !delegate.isAlive() || cancellationToken.isCanceled) return null;
      return PdfImageWithScaleAndRect(await img.createImage(), scale, rect);
    } catch (e) {
      return null; // ignore error
    } finally {
      img?.dispose();
    }
  }

  final _pageImages = <int, PdfImageWithScale>{};
  final _pageImagesPartial = <int, PdfImageWithScaleAndRect>{};
  final _pageImageRenderingTimers = <int, Timer>{};
  final _cancellationTokens = <int, List<PdfPageRenderCancellationToken>>{};
  final _pageImagePartialRenderingRequests = <int, _PdfPartialImageRenderingRequest>{};

  void _addCancellationToken(int pageNumber, PdfPageRenderCancellationToken token) {
    var tokens = _cancellationTokens.putIfAbsent(pageNumber, () => []);
    tokens.add(token);
  }

  /// Releases the partial (real size) image cache.
  void releasePartialImageCache() {
    for (final request in _pageImagePartialRenderingRequests.values) {
      request.cancel();
    }
    _pageImagePartialRenderingRequests.clear();
    for (final image in _pageImagesPartial.values) {
      image.image.dispose();
    }
    _pageImagesPartial.clear();
  }

  /// Releases all image caches.
  void releaseAllImageCache() {
    for (final timer in _pageImageRenderingTimers.values) {
      timer.cancel();
    }
    _pageImageRenderingTimers.clear();
    for (final request in _pageImagePartialRenderingRequests.values) {
      request.cancel();
    }
    _pageImagePartialRenderingRequests.clear();
    for (final image in _pageImages.values) {
      image.image.dispose();
    }
    _pageImages.clear();
    for (final image in _pageImagesPartial.values) {
      image.image.dispose();
    }
    _pageImagesPartial.clear();
  }

  /// Cancels pending rendering requests for the specified page.
  void cancelPendingRequests(int pageNumber) {
    final tokens = _cancellationTokens[pageNumber];
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel();
      }
      tokens.clear();
    }
  }

  /// Cancels all pending rendering requests.
  void cancelAllPendingRequests() {
    for (final pageNumber in _cancellationTokens.keys) {
      cancelPendingRequests(pageNumber);
    }
    _cancellationTokens.clear();
  }

  /// Removes the image cache for the specified page.
  void removeImageCacheForPage(int pageNumber) {
    final removed = _pageImages.remove(pageNumber);
    if (removed != null) {
      removed.image.dispose();
    }
    _pageImagesPartial.remove(pageNumber)?.dispose();
  }

  /// Removes image caches if the total bytes consumed exceeds the limit.
  ///
  /// [pageNumbers] is the list of page numbers to consider for removal.
  /// [acceptableBytes] is the maximum acceptable bytes for the cache.
  /// [currentVisibleRect] is the currently visible rectangle in the document coordinate space.
  /// [dist] is a function that returns the distance from the current page for a given page number.
  void removeImageCacheIfCacheBytesExceedsLimit(
    List<int> pageNumbers,
    int acceptableBytes,
    Rect currentVisibleRect, {
    double Function(int pageNumber)? dist,
  }) {
    if (pageNumbers.isEmpty) return;

    final currentPosition = currentVisibleRect.center;
    dist ??= (pageNumber) {
      final a = delegate.getPageRect(pageNumber);
      if (a == null) return double.infinity;
      return (a.center - currentPosition).distanceSquared;
    };

    pageNumbers.sort((a, b) => dist!(b).compareTo(dist(a)));
    int getBytesConsumed(ui.Image? image) => image == null ? 0 : (image.width * image.height * 4).toInt();
    var bytesConsumed =
        _pageImages.values.fold(0, (sum, e) => sum + getBytesConsumed(e.image)) +
        _pageImagesPartial.values.fold(0, (sum, e) => sum + getBytesConsumed(e.image));
    for (final key in pageNumbers) {
      final removed = _pageImages.remove(key);
      if (removed != null) {
        bytesConsumed -= getBytesConsumed(removed.image);
        removed.image.dispose();
      }
      final removedPartial = _pageImagesPartial.remove(key);
      if (removedPartial != null) {
        bytesConsumed -= getBytesConsumed(removedPartial.image);
        removedPartial.dispose();
      }
      if (bytesConsumed <= acceptableBytes) {
        break;
      }
    }
  }
}

class _PdfPartialImageRenderingRequest {
  _PdfPartialImageRenderingRequest(this.timer, this.cancellationToken);
  final Timer timer;
  final PdfPageRenderCancellationToken cancellationToken;

  void cancel() {
    timer.cancel();
    cancellationToken.cancel();
  }
}

/// A class that holds a rendered PDF page image along with its scale.
///
/// Used for preview images.
class PdfImageWithScale {
  /// Creates a new instance of [PdfImageWithScale].
  const PdfImageWithScale(this.image, this.scale);

  /// The rendered image.
  final ui.Image image;

  /// The scale of the image.
  final double scale;

  /// The width of the image.
  int get width => image.width;

  /// The height of the image.
  int get height => image.height;

  /// Disposes the image.
  void dispose() {
    image.dispose();
  }
}

/// A class that holds a rendered PDF page partial image along with its scale and rectangle.
///
/// Used for real-size partial (cropped) images.
class PdfImageWithScaleAndRect extends PdfImageWithScale {
  /// Creates a new instance of [PdfImageWithScaleAndRect].
  const PdfImageWithScaleAndRect(super.image, super.scale, this.rect);

  /// The rectangle of the image in the document coordinate space.
  final Rect rect;

  /// Draws the image onto the given canvas on the [rect].
  void draw(Canvas canvas, [FilterQuality filterQuality = FilterQuality.low]) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      rect,
      Paint()..filterQuality = filterQuality,
    );
  }
}
