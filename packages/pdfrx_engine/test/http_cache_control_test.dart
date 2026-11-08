import 'package:pdfrx_engine/src/native/http_cache_control.dart';
import 'package:test/test.dart';

void main() {
  test('parses whitespace and case in Cache-Control directives', () {
    final state = HttpCacheControlState.fromHeaders({
      'cache-control': 'must-revalidate, public, Max-Age=600, no-transform',
      'date': 'Sun, 06 Nov 1994 08:49:37 GMT',
    });

    expect(state.cacheControl.public, isTrue);
    expect(state.cacheControl.mustRevalidate, isTrue);
    expect(state.cacheControl.noTransform, isTrue);
    expect(state.cacheControl.maxAge, 600);
    expect(state.isFresh(now: DateTime.utc(1994, 11, 6, 8, 55)), isTrue);
    expect(state.isStale(now: DateTime.utc(1994, 11, 6, 9, 0)), isTrue);
  });

  test('no-store conversion accepts directive whitespace', () {
    final state = HttpCacheControlState.fromHeaders({
      'cache-control': 'private, no-store',
    }, maxAgeForNoStore: const Duration(seconds: 45));

    expect(state.cacheControl.private, isTrue);
    expect(state.cacheControl.noStore, isFalse);
    expect(state.cacheControl.noCache, isTrue);
    expect(state.cacheControl.maxAge, 45);
  });

  test('If-Modified-Since uses two-digit RFC HTTP date fields', () {
    final state = HttpCacheControlState.fromHeaders({'last-modified': 'Sun, 06 Nov 1994 08:09:07 GMT'});

    expect(state.getHeadersForFetch(), {'If-Modified-Since': 'Sun, 06 Nov 1994 08:09:07 GMT'});
    expect(DateTime.utc(2026, 1, 2, 3, 4, 5).toHttpDate(), 'Fri, 02 Jan 2026 03:04:05 GMT');
  });
}
