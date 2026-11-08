import 'package:test/test.dart';

import '../lib/src/pdfium_archive_integrity.dart';

void main() {
  test('rejects a corrupted archive', () {
    expect(
      () => verifyPdfiumArchive('pdfium-win-x64.tgz', [0x1f, 0x8b, 0]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
  });

  test('rejects an archive without a pinned digest', () {
    expect(
      () => verifyPdfiumArchive('pdfium-mac-univ.tgz', const []),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No pinned SHA-256'),
        ),
      ),
    );
  });

  test('pins every archive the hook downloads', () {
    final archives = [
      for (final arch in ['arm', 'arm64', 'x64', 'x86']) ...[
        'pdfium-android-$arch.tgz',
        'pdfium-linux-$arch.tgz',
      ],
      for (final arch in ['arm64', 'x64', 'x86']) 'pdfium-win-$arch.tgz',
      for (final arch in ['arm64', 'x64']) 'pdfium-mac-$arch.tgz',
    ];
    expect(pdfiumArchiveSha256.keys, unorderedEquals(archives));
    for (final digest in pdfiumArchiveSha256.values) {
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });
}
