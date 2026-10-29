// Run separately from tests that initialize PDFium without the process gate.
import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import 'hebrew_native.dart';
import 'background_worker_task_test.dart' show registerWorkerShutdownTests;
import 'pdf_progressive_render_test.dart' show registerProgressiveRenderTests;
import 'utils.dart';

void main() {
  setUpAll(
    () => pdfrxInitialize(tmpPath: tmpRoot.path, processWidePdfiumGate: true),
  );
  tearDownAll(() => PdfrxEntryFunctions.instance.stopBackgroundWorker());
  registerHebrewNativeTests();
  registerProgressiveRenderTests();

  test('independent workers can render, stop, and reopen while another document remains live', () async {
    stderr.writeln('GATE main: opening document');
    final document = await PdfDocument.openFile(
      '../pdfrx/example/viewer/assets/hello.pdf',
    );
    try {
      for (var round = 0; round < 3; round++) {
        stderr.writeln('GATE main: round $round starting isolates');
        await Future.wait(
          List.generate(
            4,
            (_) => Isolate.run(_exerciseEngine),
          ),
        );
        stderr.writeln('GATE main: round $round isolates done');
        final image = await document.pages.first.render(
          width: 100,
          height: 100,
        );
        expect(image, isNotNull);
        image!.dispose();
        expect((await document.pages.first.loadText())!.fullText, isNotEmpty);
      }
    } finally {
      stderr.writeln('GATE main: disposing document');
      await document.dispose();
      stderr.writeln('GATE main: document disposed');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('overlapping and nested handle actions release the gate after awaits and errors', () async {
    final entry = PdfrxEntryFunctions.instance;
    final events = <int>[];
    await Future.wait([
      entry.suspendPdfiumWorkerDuringAction(() async {
        events.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await entry.suspendPdfiumWorkerDuringAction(() => events.add(2));
        events.add(3);
      }),
      entry.suspendPdfiumWorkerDuringAction(() => events.add(4)),
    ]);
    expect(events, [1, 2, 3, 4]);
    await expectLater(
      entry.suspendPdfiumWorkerDuringAction(() => throw StateError('test')),
      throwsStateError,
    );
    expect(await entry.compute((_) => 42, null), 42);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('gate configuration cannot change after worker initialization', () {
    expect(() => Pdfrx.useProcessWidePdfiumGate = false, throwsStateError);
    expect(Pdfrx.useProcessWidePdfiumGate, isTrue);
  });
  registerWorkerShutdownTests();
}

Future<void> _exerciseEngine() async {
  final id = Isolate.current.hashCode;
  void trace(String stage) => stderr.writeln('GATE i$id: $stage');
  trace('initialize start');
  await pdfrxInitialize(tmpPath: tmpRoot.path, processWidePdfiumGate: true);
  trace('initialize done');
  for (var i = 0; i < 5; i++) {
    trace('iteration $i open start');
    final document = await PdfDocument.openFile(
      '../pdfrx/example/viewer/assets/hello.pdf',
    );
    trace('iteration $i open done, render start');
    try {
      final image = await document.pages.first.render(width: 100, height: 100);
      if (image == null) throw StateError('render failed');
      image.dispose();
      trace('iteration $i render done, text start');
      if ((await document.pages.first.loadText())!.fullText.isEmpty)
        throw StateError('text extraction failed');
    } finally {
      trace('iteration $i document dispose start');
      await document.dispose();
      trace('iteration $i document dispose done');
    }
    trace('iteration $i worker stop start');
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
    trace('iteration $i worker stop done');
  }
}
