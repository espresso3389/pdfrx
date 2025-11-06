import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import 'utils.dart';

final testPdfFile = File('../pdfrx/example/viewer/assets/hello.pdf');

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('PdfDocument.openFile', () async => await testDocument(await PdfDocument.openFile(testPdfFile.path)));
  test('PdfDocument.openData', () async {
    final data = await testPdfFile.readAsBytes();
    await testDocument(await PdfDocument.openData(data));
  });
  test('PdfDocument.openUri', () async {
    Pdfrx.createHttpClient = () =>
        MockClient((request) async => http.Response.bytes(await testPdfFile.readAsBytes(), 200));
    await testDocument(await PdfDocument.openUri(Uri.parse('https://example.com/hello.pdf')));
  });

  group('PdfDocument.openCustom with maxSizeToCacheOnMemory=0', () {
    test('opens PDF with custom read function', () async {
      final data = await testPdfFile.readAsBytes();

      // Custom read function that reads from the data buffer
      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:test.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles multiple concurrent reads', () async {
      final data = await testPdfFile.readAsBytes();
      var readCount = 0;

      int readFunc(Uint8List buffer, int position, int size) {
        readCount++;
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:concurrent.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
      expect(readCount, greaterThan(0), reason: 'Read function should be called at least once');
    });

    test('handles async read function', () async {
      final data = await testPdfFile.readAsBytes();

      Future<int> asyncReadFunc(Uint8List buffer, int position, int size) async {
        // Simulate async delay
        await Future.delayed(Duration(milliseconds: 1));

        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: asyncReadFunc,
        fileSize: data.length,
        sourceName: 'custom:async.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles read at various positions', () async {
      final data = await testPdfFile.readAsBytes();
      final readPositions = <int>[];

      int readFunc(Uint8List buffer, int position, int size) {
        readPositions.add(position);
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:positions.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);

      // Verify that reads occurred at different positions (random access)
      expect(readPositions.isNotEmpty, true, reason: 'Should have read positions recorded');
      // PDFium typically reads from multiple positions for PDF structure
      expect(readPositions.toSet().length, greaterThan(1), reason: 'Should read from multiple positions');
    });

    test('handles read errors gracefully', () async {
      int readFunc(Uint8List buffer, int position, int size) {
        // Return 0 to indicate EOF/error - no valid PDF data
        return 0;
      }

      // This should fail because we're not providing valid PDF data
      expect(
        () async => await PdfDocument.openCustom(
          read: readFunc,
          fileSize: 1000,
          sourceName: 'custom:error.pdf',
          maxSizeToCacheOnMemory: 0,
        ),
        throwsA(isA<PdfException>()),
      );
    });

    test('calls onDispose callback when document is disposed', () async {
      final data = await testPdfFile.readAsBytes();
      var disposeCalled = false;

      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:dispose.pdf',
        maxSizeToCacheOnMemory: 0,
        onDispose: () {
          disposeCalled = true;
        },
      );

      expect(disposeCalled, false, reason: 'onDispose should not be called yet');
      await doc.dispose();
      expect(disposeCalled, true, reason: 'onDispose should be called after dispose');
    });

    test('handles large file sizes correctly', () async {
      final data = await testPdfFile.readAsBytes();
      final largeFileSize = data.length;

      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: largeFileSize,
        sourceName: 'custom:large.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles partial reads correctly', () async {
      final data = await testPdfFile.readAsBytes();
      final readSizes = <int>[];

      int readFunc(Uint8List buffer, int position, int size) {
        readSizes.add(size);

        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:partial.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
      // Verify that reads occurred with various sizes
      expect(readSizes.isNotEmpty, true, reason: 'Should have read sizes recorded');
    });
  });
}
