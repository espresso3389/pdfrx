import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('scrollPhysicsScale takes part in equality and reload checks', () {
    const a = PdfViewerParams();
    const b = PdfViewerParams(scrollPhysicsScale: ClampingScrollPhysics());
    expect(b, isNot(equals(a)));
    expect(b.doChangesRequireReload(a), isTrue);
    expect(b, equals(const PdfViewerParams(scrollPhysicsScale: ClampingScrollPhysics())));
    expect(b.hashCode, const PdfViewerParams(scrollPhysicsScale: ClampingScrollPhysics()).hashCode);
  });
}
