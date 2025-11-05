import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../pdfrx.dart';

/// A widget that loads PDF document.
///
/// The following fragment shows how to display a PDF document from an asset:
///
/// ```dart
/// PdfDocumentViewBuilder.asset(
///   'assets/sample.pdf',
///   builder: (context, document) => ListView.builder(
///     itemCount: document?.pages.length ?? 0,
///     itemBuilder: (context, index) {
///       return Container(
///         margin: const EdgeInsets.all(8),
///         height: 240,
///         child: Column(
///           children: [
///             SizedBox(
///               height: 220,
///               child: PdfPageView(
///                 document: document,
///                 pageNumber: index + 1,
///               ),
///             ),
///             Text('${index + 1}'),
///           ],
///         ),
///       );
///     },
///   ),
/// ),
/// ```
class PdfDocumentViewBuilder extends StatefulWidget {
  const PdfDocumentViewBuilder({required this.documentRef, required this.builder, super.key});

  PdfDocumentViewBuilder.asset(
    String assetName, {
    required this.builder,
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefAsset(
         assetName,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
         autoDispose: autoDispose,
       );

  PdfDocumentViewBuilder.file(
    String filePath, {
    required this.builder,
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,

    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefFile(
         filePath,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
         autoDispose: autoDispose,
       );

  PdfDocumentViewBuilder.uri(
    Uri uri, {
    required this.builder,
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    bool autoDispose = true,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) : documentRef = PdfDocumentRefUri(
         uri,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
         autoDispose: autoDispose,
         preferRangeAccess: preferRangeAccess,
         headers: headers,
         withCredentials: withCredentials,
       );

  /// A reference to the PDF document.
  final PdfDocumentRef documentRef;

  /// A builder that builds a widget tree with the PDF document.
  final PdfDocumentViewBuilderFunction builder;

  @override
  State<PdfDocumentViewBuilder> createState() => _PdfDocumentViewBuilderState();

  static PdfDocumentViewBuilder? maybeOf(BuildContext context) {
    return context.findAncestorWidgetOfExactType<PdfDocumentViewBuilder>();
  }
}

class _PdfDocumentViewBuilderState extends State<PdfDocumentViewBuilder> {
  StreamSubscription<PdfDocumentEvent>? _updateSubscription;

  @override
  void initState() {
    super.initState();
    pdfrxFlutterInitialize();
    widget.documentRef.resolveListenable()
      ..addListener(_onDocumentChanged)
      ..load();
    _onDocumentChanged();
  }

  @override
  void didUpdateWidget(covariant PdfDocumentViewBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.documentRef != oldWidget.documentRef) {
      oldWidget.documentRef.resolveListenable().removeListener(_onDocumentChanged);
      widget.documentRef.resolveListenable()
        ..addListener(_onDocumentChanged)
        ..load();
      _onDocumentChanged();
    }
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    widget.documentRef.resolveListenable().removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    if (mounted) {
      _updateSubscription?.cancel();
      final document = widget.documentRef.resolveListenable().document;
      _updateSubscription = document?.events.listen((event) {
        if (mounted && event.type == PdfDocumentEventType.pageStatusChanged) {
          setState(() {});
        }
      });
      document?.loadPagesProgressively();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.documentRef.resolveListenable().document);
  }
}

/// A function that builds a widget tree with the PDF document.
typedef PdfDocumentViewBuilderFunction = Widget Function(BuildContext context, PdfDocument? document);

/// Function to calculate the size of the page based on the size of the widget.
///
/// [biggestSize] is the size of the widget.
/// [page] is the page to be displayed.
/// [rotationOverride] is the rotation to override the page rotation.
///
/// The function returns the size of the page.
typedef PdfPageViewSizeCallback = Size Function(Size biggestSize, PdfPage page, PdfPageRotation? rotationOverride);

/// Function to build a widget that wraps the page image.
///
/// It is often used to decorate the page image with a border or a shadow,
/// to set the page background color, etc.
///
/// [context] is the build context.
/// [pageSize] is the size of the page.
/// [page] is the page to be displayed.
/// [pageImage] is the page image; it is null if the page is not rendered yet.
/// The image size may be different from [pageSize] because of the screen DPI
/// or some other reasons.
typedef PdfPageViewDecorationBuilder =
    Widget Function(BuildContext context, Size pageSize, PdfPage page, RawImage? pageImage);

/// A widget that displays a page of a PDF document.
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    required this.document,
    required this.pageNumber,
    this.rotationOverride,
    this.maximumDpi = 300,
    this.alignment = Alignment.center,
    this.decoration,
    this.backgroundColor,
    this.pageSizeCallback,
    this.decorationBuilder,
    super.key,
  });

  /// The PDF document.
  final PdfDocument? document;

  /// The page number to be displayed. (The first page is 1).
  final int pageNumber;

  /// The rotation to override the page rotation.
  final PdfPageRotation? rotationOverride;

  /// The maximum DPI of the page image. The default value is 300.
  ///
  /// The value is used to limit the actual image size to avoid excessive memory usage.
  final double maximumDpi;

  /// The alignment of the page image within the widget.
  final AlignmentGeometry alignment;

  /// The decoration of the page image.
  ///
  /// To disable the default drop-shadow, set [decoration] to `BoxDecoration(color: Colors.white)` or such.
  final Decoration? decoration;

  /// The background color of the page.
  final Color? backgroundColor;

  /// The callback to calculate the size of the page based on the size of the widget.
  final PdfPageViewSizeCallback? pageSizeCallback;

  /// The builder to build a widget that wraps the page image.
  ///
  /// It replaces the default decoration builder such as background color
  /// and drop-shadow.
  final PdfPageViewDecorationBuilder? decorationBuilder;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  ui.Image? _image;
  Size? _pageSize;
  PdfPageRenderCancellationToken? _cancellationToken;
  StreamSubscription<PdfDocumentEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToDocumentEvents();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _clearCache(refresh: false);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.document != oldWidget.document ||
        widget.pageNumber != oldWidget.pageNumber ||
        widget.rotationOverride != oldWidget.rotationOverride) {
      _clearCache();
      _subscribeToDocumentEvents();
    }
  }

  void _clearCache({bool refresh = true}) {
    _image?.dispose();
    _image = null;
    _pageSize = null;
    _cancellationToken?.cancel();
    _cancellationToken = null;
    if (refresh && mounted) {
      setState(() {});
    }
  }

  void _subscribeToDocumentEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = widget.document?.events.listen((event) {
      if (event is PdfDocumentPageStatusChangedEvent) {
        if (event.changes.keys.contains(widget.pageNumber)) {
          _clearCache();
        }
      }
    });
  }

  Widget _defaultDecorationBuilder(BuildContext context, Size pageSize, PdfPage page, RawImage? pageImage) {
    return Align(
      alignment: widget.alignment,
      child: AspectRatio(
        aspectRatio: pageSize.width / pageSize.height,
        child: Stack(
          children: [
            Container(
              decoration:
                  widget.decoration ??
                  BoxDecoration(
                    color: pageImage == null ? widget.backgroundColor ?? Colors.white : Colors.transparent,
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2))],
                  ),
            ),
            if (pageImage != null) pageImage,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final query = MediaQuery.of(context);
        _updateImage(constraints.biggest * query.devicePixelRatio);

        if (_pageSize != null) {
          final decorationBuilder = widget.decorationBuilder ?? _defaultDecorationBuilder;
          final scale = min(constraints.maxWidth / _pageSize!.width, constraints.maxHeight / _pageSize!.height);
          return decorationBuilder(
            context,
            _pageSize!,
            widget.document!.pages[widget.pageNumber - 1],
            _image != null
                ? RawImage(
                    image: _image,
                    width: _pageSize!.width * scale,
                    height: _pageSize!.height * scale,
                    fit: BoxFit.fill,
                  )
                : null,
          );
        }
        return const SizedBox();
      },
    );
  }

  Future<void> _updateImage(Size size) async {
    final document = widget.document;
    if (document == null || widget.pageNumber < 1 || widget.pageNumber > document.pages.length || size.isEmpty) {
      return;
    }
    final page = document.pages[widget.pageNumber - 1];

    final Size pageSize;
    if (widget.pageSizeCallback != null) {
      pageSize = widget.pageSizeCallback!(size, page, widget.rotationOverride);
    } else {
      final swapWH = ((widget.rotationOverride ?? page.rotation).index - page.rotation.index) & 1 == 1;
      final w = swapWH ? page.height : page.width;
      final h = swapWH ? page.width : page.height;

      final scale = min(widget.maximumDpi / 72, min(size.width / w, size.height / h));
      pageSize = Size(w * scale, h * scale);
    }

    if (pageSize == _pageSize) return;
    _pageSize = pageSize;

    _cancellationToken?.cancel();
    _cancellationToken = page.createCancellationToken();
    final pageImage = await page.render(
      fullWidth: pageSize.width,
      fullHeight: pageSize.height,
      rotationOverride: widget.rotationOverride,
      cancellationToken: _cancellationToken,
    );
    if (pageImage == null) return;
    try {
      final newImage = await pageImage.createImage();
      pageImage.dispose();
      _image = newImage;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      developer.log('Error creating image: $e');
      pageImage.dispose();
    }
  }
}
