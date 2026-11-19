import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('semantics requested before the first paint receives loaded links', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final document = _Document(1);
      addTearDown(document.dispose);
      final controller = PdfViewerController();
      await tester.pumpWidget(_viewer(document, controller));
      await _pump(tester);
      expect((document.pages.single as _Page).calls, [true]);
      expect(find.byKey(const Key('#__pageLinkSemantics__:1:0')), findsOneWidget);
      await _unmount(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('scrolling releases link lists outside the page extent', (tester) async {
    final document = _Document(40);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pump(tester);
    final first = document.pages.first as _Page;
    expect(first.calls, [true]);
    await controller.goToPage(pageNumber: 30, duration: Duration.zero);
    await _pump(tester);
    expect((document.pages[29] as _Page).calls, isNotEmpty);
    await controller.goToPage(pageNumber: 1, duration: Duration.zero);
    await _pump(tester);
    expect(first.calls, [true, true], reason: 'viewer must release metadata for pages outside its extent');
    await _unmount(tester);
  });

  testWidgets('scrolling past 100 pages does not extract links for abandoned queued pages', (tester) async {
    final document = _Document(100);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final gate = Completer<List<PdfLink>>();
    final first = document.pages.first as _Page;
    first.load = (_) => gate.future;
    await tester.pumpWidget(_viewer(document, controller));
    await _pump(tester);
    expect(first.calls, [true]);
    for (var pageNumber = 2; pageNumber <= 100; pageNumber++) {
      await controller.goToPage(pageNumber: pageNumber, duration: Duration.zero);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(document.pages.skip(1).cast<_Page>().every((page) => page.calls.isEmpty), isTrue);
    gate.complete(_links('finished'));
    await _pump(tester);
    final extractions = document.pages.cast<_Page>().fold(0, (count, page) => count + page.calls.length);
    debugPrint('After scrolling past 100 pages during one slow extraction: $extractions link extractions.');
    expect(extractions, 2, reason: 'only the already-running and currently visible pages need extraction');
    expect((document.pages.last as _Page).calls, [true]);
    await _unmount(tester);
  });

  testWidgets('changing auto detection reloads links and ignores the old pending mode', (tester) async {
    final document = _Document(1);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final page = document.pages.single as _Page;
    final gate = Completer<List<PdfLink>>();
    page.load = (auto) => auto ? gate.future : Future.value(_links('annotation'));
    final painted = <String>[];
    void onPaint(List<PdfLink> links) => painted.add(links.single.url!.path);
    await tester.pumpWidget(_viewer(document, controller, onPaint: onPaint));
    await _pump(tester);
    expect(page.calls, [true]);
    await tester.pumpWidget(_viewer(document, controller, autoDetect: false, onPaint: onPaint));
    gate.complete(_links('auto'));
    await _pump(tester);
    expect(page.calls, [true, false]);
    expect(painted, isNot(contains('/auto')));
    expect(painted, contains('/annotation'));
    await _unmount(tester);
  });

  testWidgets('hiding a viewer drops a late completion and showing it can reload', (tester) async {
    final document = _Document(1);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final page = document.pages.single as _Page;
    final gate = Completer<List<PdfLink>>();
    page.load = (_) => gate.future;
    final painted = <String>[];
    void onPaint(List<PdfLink> links) => painted.add(links.single.url!.path);
    await tester.pumpWidget(_viewer(document, controller, onPaint: onPaint));
    await _pump(tester);
    expect(page.calls, [true]);
    await tester.pumpWidget(_viewer(document, controller, visible: false, onPaint: onPaint));
    gate.complete(_links('late'));
    await _pump(tester);
    expect(painted, isEmpty);
    page.load = (_) async => _links('current');
    await tester.pumpWidget(_viewer(document, controller, onPaint: onPaint));
    await _pump(tester);
    expect(page.calls, [true, true]);
    expect(painted, isNot(contains('/late')));
    expect(painted, contains('/current'));
    await _unmount(tester);
  });

  testWidgets('page replacement during link loading publishes only the replacement', (tester) async {
    final document = _Document(1);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final gate = Completer<List<PdfLink>>();
    final oldPage = document.pages.single as _Page;
    oldPage.load = (_) => gate.future;
    final painted = <String>[];
    await tester.pumpWidget(_viewer(document, controller, onPaint: (links) => painted.add(links.single.url!.path)));
    await _pump(tester);
    final newPage = _Page(document, 1)..load = (_) async => _links('new');
    document.replace(newPage);
    await tester.pump();
    gate.complete(_links('old'));
    await _pump(tester);
    expect(newPage.calls, [true]);
    expect(painted, isNot(contains('/old')));
    expect(painted, contains('/new'));
    await _unmount(tester);
  });
}

Widget _viewer(
  _Document document,
  PdfViewerController controller, {
  bool visible = true,
  bool autoDetect = true,
  void Function(List<PdfLink>)? onPaint,
}) => MaterialApp(
  home: PdfViewer(
    PdfDocumentRefDirect(document, autoDispose: false),
    controller: controller,
    params: PdfViewerParams(
      isVisible: visible,
      verticalCacheExtent: 0,
      horizontalCacheExtent: 0,
      sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: (_, _, _, _) => 1),
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: (_) {},
        enableAutoLinkDetection: autoDetect,
        customPainter: onPaint == null ? null : (_, _, _, links) => onPaint(links),
      ),
      behaviorControlParams: const PdfViewerBehaviorControlParams(
        pageImageCachingDelay: Duration.zero,
        partialImageLoadingDelay: Duration.zero,
        trailingPageLoadingDelay: Duration.zero,
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

List<PdfLink> _links(String name) => [
  PdfLink(const [PdfRect(10, 700, 100, 680)], url: Uri.parse('https://example.com/$name')),
];

class _Document extends PdfDocument {
  _Document(int count) : super(sourceName: 'test:links:${_nextId++}') {
    pages = List.generate(count, (index) => _Page(this, index + 1));
  }

  static int _nextId = 0;
  final _events = StreamController<PdfDocumentEvent>.broadcast();

  @override
  late List<PdfPage> pages;

  @override
  bool get isEncrypted => false;

  @override
  PdfPermissions? get permissions => null;

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;

  void replace(PdfPage page) {
    pages[page.pageNumber - 1] = page;
    _events.add(
      PdfDocumentPageStatusChangedEvent(this, changes: {page.pageNumber: PdfPageStatusChange.modified(page: page)}),
    );
  }

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {}

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

class _Page extends Fake implements PdfPage {
  _Page(this.document, this.pageNumber);

  @override
  final PdfDocument document;

  @override
  final int pageNumber;

  @override
  bool get isLoaded => true;

  @override
  double get width => 600;

  @override
  double get height => 800;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  final calls = <bool>[];
  Future<List<PdfLink>> Function(bool) load = (_) async => _links('default');

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) {
    calls.add(enableAutoLinkDetection);
    return load(enableAutoLinkDetection);
  }

  @override
  Future<PdfPageRawText?> loadText() async => null;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Token();

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

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;

  @override
  void cancel() => isCanceled = true;
}
