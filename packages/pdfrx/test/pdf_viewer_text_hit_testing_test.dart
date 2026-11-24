import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as iv;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  testWidgets('dense-page drag selects the linear-oracle endpoints with fewer geometry visits', (tester) async {
    final document = _Document();
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final counted = await _countedText(document);
    expect(counted.text.charRects.length, greaterThanOrEqualTo(10000));

    for (final endpoints in [(2425, 4850), (3542, 1913), (1324, 4291)]) {
      final visits = await _drag(tester, controller, document, counted, endpoints.$1, endpoints.$2);
      expect(
        visits,
        lessThan(1024),
        reason: 'A drag should inspect nearby groups, not most of the 10k-character page.',
      );
    }
    await _unmount(tester);
  });

  testWidgets('content replacement, cache release and document swap do not reuse old hit geometry', (tester) async {
    final document = _Document();
    final replacement = _Document(character: 'z', offsetX: 60);
    addTearDown(document.dispose);
    addTearDown(replacement.dispose);
    final controller = await _mount(tester, document);
    final original = await _countedText(document);
    await _drag(tester, controller, document, original, 2425, 4850);

    document.replacePage(character: 'b', offsetX: 45);
    await tester.pump();
    final changed = await _countedText(document);
    expect(changed.text, isNot(same(original.text)));
    original.counter.visits = 0;
    expect(await _drag(tester, controller, document, changed, 3542, 1913), lessThan(1024));
    expect(original.counter.visits, 0);
    expect(controller.textSelectionDelegate.selectedTextIfLoaded, contains('b'));

    controller.releaseCachedResources(keepVisible: false, keepSelection: false);
    expect(PdfPageTextCache.forDocument(document).get(1), isNull);
    final reloaded = await _countedText(document);
    expect(reloaded.text, isNot(same(changed.text)));
    changed.counter.visits = 0;
    expect(await _drag(tester, controller, document, reloaded, 1324, 4291), lessThan(1024));
    expect(changed.counter.visits, 0);

    var ready = false;
    await tester.pumpWidget(_viewer(replacement, controller, onReady: () => ready = true));
    await _pumpUntil(tester, () => ready && identical(controller.document, replacement));
    final swapped = await _countedText(replacement);
    reloaded.counter.visits = 0;
    expect(await _drag(tester, controller, replacement, swapped, 2425, 4850), lessThan(1024));
    expect(reloaded.counter.visits, 0);
    expect(controller.textSelectionDelegate.selectedTextIfLoaded, contains('z'));
    await _unmount(tester);
  });

  testWidgets('dense-page selection handles extend through text margins without scanning every character', (
    tester,
  ) async {
    final document = _Document();
    addTearDown(document.dispose);
    final controller = await _mount(tester, document, handles: true);
    final counted = await _countedText(document);
    final selection = controller.textSelectionDelegate;
    await selection.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(counted.text, 0), PdfTextSelectionPoint(counted.text, 4)),
    );
    await tester.pump();
    final handle = tester.widget<GestureDetector>(
      find
          .descendant(of: find.byKey(const Key('pdfrxAnchorBPositioned')), matching: find.byType(GestureDetector))
          .first,
    );
    final pageRect = controller.layout.pageLayouts.first;
    final start = controller.documentToGlobal(
      counted.text.charRects[4].toRectInDocument(page: document.pages.first, pageRect: pageRect).bottomRight,
    )!;
    handle.onPanStart!(DragStartDetails(globalPosition: start));
    final belowText = controller.documentToGlobal(
      const PdfPoint(300, 5).toOffsetInDocument(page: document.pages.first, pageRect: pageRect),
    )!;
    counted.counter.visits = 0;
    handle.onPanUpdate!(DragUpdateDetails(globalPosition: belowText, delta: belowText - start));
    expect(selection.textSelectionPointRange!.end.index, counted.text.charRects.length - 1);
    expect(counted.counter.visits, lessThan(256));
    handle.onPanCancel!();
    await _unmount(tester);
  });
}

Future<int> _drag(
  WidgetTester tester,
  PdfViewerController controller,
  _Document document,
  _CountedText counted,
  int startIndex,
  int endIndex,
) async {
  await controller.textSelectionDelegate.clearTextSelection();
  final page = document.pages.first;
  final pageRect = controller.layout.pageLayouts.first;
  final startPoint = counted.text.charRects[startIndex].center;
  final endPoint = counted.text.charRects[endIndex].center;
  final expectedStart = _linearIndex(counted.text, startPoint);
  final expectedEnd = _linearIndex(counted.text, endPoint);
  final start = controller.documentToGlobal(startPoint.toOffsetInDocument(page: page, pageRect: pageRect))!;
  final end = controller.documentToGlobal(endPoint.toOffsetInDocument(page: page, pageRect: pageRect))!;
  final detector = tester
      .widgetList<GestureDetector>(
        find.descendant(of: find.byType(iv.InteractiveViewer), matching: find.byType(GestureDetector)),
      )
      .firstWhere((widget) => widget.onPanStart != null);

  counted.counter.visits = 0;
  detector.onPanStart!(DragStartDetails(globalPosition: start));
  detector.onPanUpdate!(DragUpdateDetails(globalPosition: end, delta: end - start));
  final range = controller.textSelectionDelegate.textSelectionPointRange!;
  expect(range.start.index, expectedStart < expectedEnd ? expectedStart : expectedEnd);
  expect(range.end.index, expectedStart < expectedEnd ? expectedEnd : expectedStart);
  expect(range.start.text, same(counted.text));
  expect(range.end.text, same(counted.text));
  final visits = counted.counter.visits;
  detector.onPanEnd!(DragEndDetails(globalPosition: end));
  return visits;
}

int _linearIndex(PdfPageText text, PdfPoint point) {
  var distance = double.infinity;
  var result = 0;
  for (var i = 0; i < text.charRects.length; i++) {
    final rect = text.charRects[i];
    if (rect.containsPoint(point)) return i;
    final candidate = rect.distanceSquaredTo(point);
    if (candidate < distance) {
      distance = candidate;
      result = i;
    }
  }
  return result;
}

Future<_CountedText> _countedText(_Document document) async {
  final text = await PdfPageTextCache.forDocument(document).load(document.pages.first);
  final counter = _Counter();
  for (var i = 0; i < text.charRects.length; i++) {
    final rect = text.charRects[i];
    text.charRects[i] = _CountedRect(rect.left, rect.top, rect.right, rect.bottom, counter);
  }
  return _CountedText(text, counter);
}

Future<PdfViewerController> _mount(WidgetTester tester, _Document document, {bool handles = false}) async {
  final controller = PdfViewerController();
  var ready = false;
  await tester.pumpWidget(_viewer(document, controller, handles: handles, onReady: () => ready = true));
  await _pumpUntil(tester, () => ready);
  return controller;
}

Widget _viewer(_Document document, PdfViewerController controller, {bool handles = false, void Function()? onReady}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            height: 400,
            child: PdfViewer(
              PdfDocumentRefDirect(document, autoDispose: false),
              controller: controller,
              params: PdfViewerParams(
                onViewerReady: (_, _) => onReady?.call(),
                horizontalCacheExtent: 0,
                verticalCacheExtent: 0,
                textSelectionParams: PdfTextSelectionParams(
                  enableSelectionHandles: handles,
                  showContextMenuAutomatically: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var frame = 0; frame < 100 && !condition(); frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
  }
  expect(condition(), isTrue);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
}

class _Counter {
  int visits = 0;
}

class _CountedText {
  _CountedText(this.text, this.counter);
  final PdfPageText text;
  final _Counter counter;
}

class _CountedRect extends PdfRect {
  _CountedRect(super.left, super.top, super.right, super.bottom, this.counter);
  final _Counter counter;

  @override
  double distanceSquaredTo(PdfPoint point) {
    counter.visits++;
    return super.distanceSquaredTo(point);
  }
}

class _Document extends PdfDocument {
  _Document({this.character = 'a', this.offsetX = 20}) : super(sourceName: 'test:hit-testing:${_nextId++}') {
    _pages = [_Page(this)];
  }

  static int _nextId = 0;
  String character;
  double offsetX;
  final _events = StreamController<PdfDocumentEvent>.broadcast(sync: true);
  late List<PdfPage> _pages;

  void replacePage({required String character, required double offsetX}) {
    this.character = character;
    this.offsetX = offsetX;
    final page = _Page(this);
    _pages = [page];
    _events.add(PdfDocumentPageStatusChangedEvent(this, changes: {1: PdfPageStatusChange.modified(page: page)}));
  }

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;
  @override
  bool get isEncrypted => false;
  @override
  PdfPermissions? get permissions => null;
  @override
  List<PdfPage> get pages => _pages;
  @override
  set pages(List<PdfPage> value) => _pages = List.of(value);
  @override
  Future<void> dispose() => _events.close();
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    await onPageLoadProgress?.call(1, 1, data);
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {}
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
  @override
  Future<bool> assemble() async => false;
  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async => Uint8List(0);
  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int nativeDocumentHandle) task) async => task(0);
}

class _Page implements PdfPage {
  _Page(this.document);
  @override
  final _Document document;
  @override
  int get pageNumber => 1;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  bool get isLoaded => true;

  @override
  Future<List<PdfPageImageObject>> loadImages() async => const [];

  @override
  Future<PdfPageRawText?> loadText() async {
    final text = StringBuffer();
    final rects = <PdfRect>[];
    for (var row = 0; row < 100; row++) {
      final top = 770 - row * 7.0;
      for (var col = 0; col < 100; col++) {
        final left = document.offsetX + col * 5.0;
        text.write(document.character);
        rects.add(PdfRect(left, top, left + 4, top - 5));
      }
      if (row < 99) {
        text.write('\n');
        rects.add(PdfRect(document.offsetX + 500, top, document.offsetX + 500, top - 5));
      }
    }
    return PdfPageRawText(text.toString(), rects);
  }

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => const [];
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _CancellationToken();
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
    PdfPageRenderPriority? priority,
  }) async => PdfImage.createFromBgraData(Uint8List.fromList([255, 255, 255, 255]), width: 1, height: 1);
}

class _CancellationToken implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}
