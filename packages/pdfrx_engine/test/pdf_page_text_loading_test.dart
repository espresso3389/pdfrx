import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('structured text can wait for the latest loaded page', () async {
    final document = _Document();
    addTearDown(document.eventsController.close);
    final placeholder = document.pages.single as _Page;
    var completed = false;
    final loading = placeholder.loadStructuredText(ensureLoaded: true).then((text) {
      completed = true;
      return text;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(placeholder.loads, 0);
    final loaded = document.publishLoadedPage();
    expect((await loading).fullText, 'word');
    expect(loaded.loads, 1);
  });

  test('the default does not wait for progressive measurement', () async {
    final document = _Document();
    addTearDown(document.eventsController.close);
    expect((await document.pages.single.loadStructuredText()).fullText, isEmpty);
  });

  test('a loaded renumbered page preserves its requested text page number', () async {
    final document = _Document();
    addTearDown(document.eventsController.close);
    final loaded = document.publishLoadedPage().withPageNumber(7);
    expect((await loaded.loadStructuredText()).pageNumber, 7);
  });

  test('waiting for a page finishes when its document event stream closes', () async {
    final document = _Document();
    final waiting = document.pages.single.waitForLoaded();
    await document.eventsController.close();
    expect(await waiting.timeout(const Duration(seconds: 1)), isNull);
  });

  test('cancellation releases the page event subscription', () async {
    final document = _Document();
    addTearDown(document.eventsController.close);
    final cancel = Completer<void>();
    final waiting = document.pages.single.waitForLoaded(cancelLoading: cancel.future);
    expect(document.eventsController.hasListener, isTrue);
    cancel.complete();
    expect(await waiting, isNull);
    expect(document.eventsController.hasListener, isFalse);
  });

  test('ensureLoaded reports document closure instead of waiting indefinitely', () async {
    final document = _Document();
    final loading = expectLater(document.pages.single.ensureLoaded(), throwsStateError);
    await document.eventsController.close();
    await loading;
  });

  test('timeout releases the page event subscription', () async {
    final document = _Document();
    addTearDown(document.eventsController.close);
    expect(await document.pages.single.waitForLoaded(timeout: const Duration(milliseconds: 1)), isNull);
    expect(document.eventsController.hasListener, isFalse);
  });
}

class _Document implements PdfDocument {
  _Document() {
    pages = [_Page(this, isLoaded: false)];
  }

  final eventsController = StreamController<PdfDocumentEvent>.broadcast(sync: true);

  @override
  late List<PdfPage> pages;

  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;

  _Page publishLoadedPage() {
    final page = _Page(this, isLoaded: true);
    pages = [page];
    eventsController.add(
      PdfDocumentPageStatusChangedEvent(this, changes: {1: PdfPageStatusChange.modified(page: page)}),
    );
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  _Page(this.document, {required this.isLoaded});

  @override
  final _Document document;

  @override
  final bool isLoaded;

  @override
  int get pageNumber => 1;

  int loads = 0;

  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    return isLoaded ? PdfPageRawText('word', List.filled(4, const PdfRect(0, 1, 1, 0))) : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
