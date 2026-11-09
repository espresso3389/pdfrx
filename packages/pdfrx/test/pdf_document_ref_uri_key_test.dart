import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  final uri = Uri.parse('https://example.org/protected.pdf');

  test('different HTTP authorization contexts cannot share a PDF document', () {
    final alice = PdfDocumentRefUri(uri, headers: {'Authorization': 'Bearer alice'});
    final bob = PdfDocumentRefUri(uri, headers: {'Authorization': 'Bearer bob'});
    final anonymous = PdfDocumentRefUri(uri);
    final withCookies = PdfDocumentRefUri(uri, withCredentials: true);

    expect(alice.key, isNot(bob.key));
    expect(alice.resolveListenable(), isNot(same(bob.resolveListenable())));
    expect(alice.key, isNot(anonymous.key));
    expect(anonymous.key, isNot(withCookies.key));
  });

  test('equivalent headers share a reference regardless of order and key casing', () {
    final first = PdfDocumentRefUri(uri, headers: {'Authorization': 'Bearer alice', 'X-Tenant': 'library'});
    final second = PdfDocumentRefUri(uri, headers: {'x-tenant': 'library', 'authorization': 'Bearer alice'});

    expect(first.key, second.key);
    expect(first.key.hashCode, second.key.hashCode);
    expect(first.resolveListenable(), same(second.resolveListenable()));
  });

  test('explicit custom reference keys remain supported', () {
    final custom = PdfDocumentRefKey('application-managed-key');
    final ref = PdfDocumentRefUri(uri, headers: {'Authorization': 'Bearer 1'}, key: custom);
    expect(ref.key, same(custom));
  });
}
