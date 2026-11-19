import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

const _imageSide = 13;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a null render retries at the same size on a later rebuild', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    fixture.calls.single.complete(null);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);

    await fixture.mount(tester);
    expect(fixture.calls, hasLength(2));
    await fixture.complete(tester, fixture.calls.last);
    expect(find.byType(RawImage), findsOneWidget);
    await fixture.unmount(tester);
  });

  testWidgets('a failed render retries at the same size on a later rebuild', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    fixture.calls.single.result.completeError(StateError('render failed'));
    await tester.pump();

    await fixture.mount(tester);
    expect(fixture.calls, hasLength(2));
    await fixture.complete(tester, fixture.calls.last);
    expect(find.byType(RawImage), findsOneWidget);
    await fixture.unmount(tester);
  });

  testWidgets('a failed decode releases its input and retries at the same size', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    final source = _Image(invalid: true);
    await fixture.complete(tester, fixture.calls.single, source: source);
    expect(source.disposeCount, 1);
    expect(find.byType(RawImage), findsNothing);

    await fixture.mount(tester);
    expect(fixture.calls, hasLength(2));
    await fixture.complete(tester, fixture.calls.last);
    expect(find.byType(RawImage), findsOneWidget);
    await fixture.unmount(tester);
  });

  for (final failure in ['null', 'error']) {
    testWidgets('a $failure result does not start an automatic retry loop while idle', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      if (failure == 'null') {
        fixture.calls.single.complete(null);
      } else {
        fixture.calls.single.result.completeError(StateError('render failed'));
      }
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(fixture.calls, hasLength(1));
      await fixture.unmount(tester);
    });
  }

  testWidgets('rebuilding while the same render is pending does not duplicate work', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    for (var i = 0; i < 20; i++) {
      await fixture.mount(tester);
    }
    expect(fixture.calls, hasLength(1));
    await fixture.complete(tester, fixture.calls.single);
    for (var i = 0; i < 20; i++) {
      await fixture.mount(tester);
    }
    expect(fixture.calls, hasLength(1));
    await fixture.unmount(tester);
  });

  for (final change in ['page', 'document', 'rotation', 'size']) {
    testWidgets('a late render cannot replace the current image after a $change change', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final old = fixture.calls.single;
      switch (change) {
        case 'page':
          fixture.pageNumber = 2;
        case 'document':
          fixture.document = fixture.otherDocument;
        case 'rotation':
          fixture.rotation = PdfPageRotation.clockwise90;
        case 'size':
          fixture.side = 160;
      }
      await fixture.mount(tester);
      final current = fixture.calls.last;
      expect(old.token.isCanceled, isTrue);
      await fixture.complete(tester, current);
      final displayed = tester.widget<RawImage>(find.byType(RawImage)).image;
      final obsoleteSource = _Image();
      await fixture.complete(tester, old, source: obsoleteSource);
      expect(obsoleteSource.disposeCount, 1);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(displayed));
      expect(fixture.calls, hasLength(2));
      await fixture.unmount(tester);
    });
  }

  testWidgets('an old error cannot clear a newer request with the same dimensions', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    final old = fixture.calls.single;
    fixture.pageNumber = 2;
    await fixture.mount(tester);
    final current = fixture.calls.last;
    old.result.completeError(StateError('obsolete failure'));
    await tester.pump();
    await fixture.mount(tester);
    expect(fixture.calls, hasLength(2));
    expect(current.token.isCanceled, isFalse);
    await fixture.complete(tester, current);
    await fixture.unmount(tester);
  });

  testWidgets('returning to the displayed size cancels an obsolete resize without rendering again', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.complete(tester, fixture.calls.single);
    final displayed = tester.widget<RawImage>(find.byType(RawImage)).image;
    fixture.side = 160;
    await fixture.mount(tester);
    final obsolete = fixture.calls.last;
    fixture.side = 100;
    await fixture.mount(tester);
    expect(fixture.calls, hasLength(2));
    expect(obsolete.token.isCanceled, isTrue);
    await fixture.complete(tester, obsolete);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(displayed));
    await fixture.unmount(tester);
  });

  for (final invalidation in ['content', 'page', 'document', 'rotation']) {
    testWidgets('a $invalidation change during decode disposes the obsolete Flutter image', (tester) async {
      final fixture = _Fixture();
      final tracker = _ImageTracker();
      addTearDown(tracker.restore);
      await fixture.mount(tester);
      final element = tester.element(find.byType(PdfPageView)) as StatefulElement;
      tracker.onCreate = () {
        tracker.onCreate = null;
        switch (invalidation) {
          case 'content':
            fixture.document.notifyChanged(fixture.pageNumber);
          case 'page':
            fixture.pageNumber = 2;
            element.owner!.buildScope(element, () => element.update(fixture.pageView()));
          case 'document':
            fixture.document = fixture.otherDocument;
            element.owner!.buildScope(element, () => element.update(fixture.pageView()));
          case 'rotation':
            fixture.rotation = PdfPageRotation.clockwise180;
            element.owner!.buildScope(element, () => element.update(fixture.pageView()));
        }
      };
      final source = _Image();
      await fixture.complete(tester, fixture.calls.single, source: source);
      expect(source.disposeCount, 1);
      expect(tracker.created, hasLength(1));
      expect(tracker.disposeCounts[tracker.created.single], 1);
      expect(find.byType(RawImage), findsNothing);
      await fixture.unmount(tester);
    });
  }

  for (final invalidation in ['null document', 'invalid page', 'zero size']) {
    testWidgets('$invalidation cancels pending work and discards its result', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final pending = fixture.calls.single;
      switch (invalidation) {
        case 'null document':
          fixture.hideDocument = true;
        case 'invalid page':
          fixture.pageNumber = 0;
        case 'zero size':
          fixture.side = 0;
      }
      await fixture.mount(tester);
      expect(pending.token.isCanceled, isTrue);
      final source = _Image();
      await fixture.complete(tester, pending, source: source);
      expect(source.disposeCount, 1);
      expect(find.byType(RawImage), findsNothing);
      await fixture.unmount(tester);
    });
  }

  testWidgets('unmounting cancels pending work and releases late input exactly once', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    final pending = fixture.calls.single;
    await tester.pumpWidget(const SizedBox());
    expect(pending.token.isCanceled, isTrue);
    final source = _Image();
    await fixture.complete(tester, pending, source: source);
    expect(source.disposeCount, 1);
    expect(tester.takeException(), isNull);
    await fixture.unmount(tester);
  });

  testWidgets('replacement and unmount dispose every successfully decoded image once', (tester) async {
    final fixture = _Fixture();
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    await fixture.mount(tester);
    await fixture.complete(tester, fixture.calls.single);
    fixture.side = 160;
    await fixture.mount(tester);
    await fixture.complete(tester, fixture.calls.last);
    await fixture.unmount(tester);
    expect(tracker.created, isNotEmpty);
    expect(tracker.created.every((image) => tracker.disposeCounts[image] == 1), isTrue);
  });
}

class _Fixture {
  _Fixture() {
    document = _Document(calls);
    otherDocument = _Document(calls);
    documents.addAll([document, otherDocument]);
  }

  final calls = <_RenderCall>[];
  final documents = <_Document>[];
  late _Document document;
  late final _Document otherDocument;
  int pageNumber = 1;
  double side = 100;
  bool hideDocument = false;
  PdfPageRotation? rotation;

  PdfPageView pageView() =>
      PdfPageView(document: hideDocument ? null : document, pageNumber: pageNumber, rotationOverride: rotation);

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Center(
          child: SizedBox(width: side, height: side, child: pageView()),
        ),
      ),
    ),
  );

  Future<void> complete(WidgetTester tester, _RenderCall call, {_Image? source}) async {
    await tester.runAsync(() async {
      final image = source ?? _Image();
      call.complete(image);
      for (var i = 0; i < 200 && image.disposeCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(image.disposeCount, 1);
    });
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (final call in calls) {
      if (!call.result.isCompleted) call.complete(null);
    }
    await tester.pump();
    for (final document in documents) {
      await document.dispose();
    }
  }
}

class _Document extends Fake implements PdfDocument {
  _Document(List<_RenderCall> calls) {
    pages = [for (var number = 1; number <= 2; number++) _Page(this, number, calls)];
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast(sync: true);
  @override
  late List<PdfPage> pages;
  @override
  Stream<PdfDocumentEvent> get events => _events.stream;
  @override
  Future<void> dispose() => _events.close();

  void notifyChanged(int pageNumber) {
    _events.add(
      PdfDocumentPageStatusChangedEvent(
        this,
        changes: {pageNumber: PdfPageStatusChange.modified(page: pages[pageNumber - 1])},
      ),
    );
  }
}

class _Page extends Fake implements PdfPage {
  _Page(this.document, this.pageNumber, this.calls);
  @override
  final _Document document;
  @override
  final int pageNumber;
  final List<_RenderCall> calls;
  @override
  double get width => 100;
  @override
  double get height => 200;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
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
  }) {
    final call = _RenderCall(cancellationToken!, Size(fullWidth!, fullHeight!));
    calls.add(call);
    return call.result.future;
  }
}

class _RenderCall {
  _RenderCall(this.token, this.size);
  final PdfPageRenderCancellationToken token;
  final Size size;
  final result = Completer<PdfImage?>();
  void complete(PdfImage? image) => result.complete(image);
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _Image implements PdfImage {
  _Image({this.invalid = false});
  final bool invalid;
  int disposeCount = 0;
  @override
  int get width => invalid ? 4000 : _imageSide;
  @override
  int get height => invalid ? 3000 : _imageSide;
  @override
  Uint8List get pixels => Uint8List(_imageSide * _imageSide * 4)..fillRange(0, _imageSide * _imageSide * 4, 255);
  @override
  void dispose() => disposeCount++;
}

class _ImageTracker {
  _ImageTracker() {
    ui.Image.onCreate = (image) {
      _previousCreate?.call(image);
      if (image.width == _imageSide && image.height == _imageSide) {
        created.add(image);
        onCreate?.call();
      }
    };
    ui.Image.onDispose = (image) {
      _previousDispose?.call(image);
      if (created.contains(image)) disposeCounts.update(image, (count) => count + 1, ifAbsent: () => 1);
    };
  }

  final _previousCreate = ui.Image.onCreate;
  final _previousDispose = ui.Image.onDispose;
  final created = Set<ui.Image>.identity();
  final disposeCounts = Map<ui.Image, int>.identity();
  void Function()? onCreate;

  void restore() {
    ui.Image.onCreate = _previousCreate;
    ui.Image.onDispose = _previousDispose;
  }
}
