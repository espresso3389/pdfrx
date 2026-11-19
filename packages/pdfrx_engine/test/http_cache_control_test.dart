import 'package:pdfrx_engine/src/native/http_cache_control.dart';
import 'package:test/test.dart';

void main() {
  test('parses whitespace and case in Cache-Control directives', () {
    final state = HttpCacheControlState.fromHeaders({
      'cache-control': 'must-revalidate, public, Max-Age=600, no-transform',
      'date': 'Sun, 06 Nov 1994 08:49:37 GMT',
    }, responseTime: DateTime.utc(1994, 11, 6, 8, 49, 37));

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

  test('max-age takes precedence over Expires and expires at the boundary', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final state = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age=60',
      'date': received.toHttpDate(),
      'expires': received.subtract(const Duration(days: 1)).toHttpDate(),
    }, responseTime: received);
    expect(state.canReuse(now: received.add(const Duration(seconds: 59))), isTrue);
    expect(state.canReuse(now: received.add(const Duration(seconds: 60))), isFalse);
  });

  test('Age, response delay, and resident time all count toward freshness', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final state = HttpCacheControlState.fromHeaders(
      {'cache-control': 'max-age=60', 'date': received.toHttpDate(), 'age': '50'},
      requestTime: received.subtract(const Duration(seconds: 3)),
      responseTime: received,
    );
    expect(state.initialAge, const Duration(seconds: 53));
    expect(state.canReuse(now: received.add(const Duration(seconds: 6))), isTrue);
    expect(state.canReuse(now: received.add(const Duration(seconds: 7))), isFalse);
    expect(HttpCacheControlState.parseDataStr(state.dataStr), state);
  });

  test('apparent age dominates a smaller Age header and future Date cannot extend max-age', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final oldDate = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age=60',
      'date': received.subtract(const Duration(seconds: 70)).toHttpDate(),
      'age': '10',
    }, responseTime: received);
    expect(oldDate.canReuse(now: received), isFalse);
    final futureDate = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age=60',
      'date': received.add(const Duration(days: 1)).toHttpDate(),
    }, responseTime: received);
    expect(futureDate.canReuse(now: received.add(const Duration(seconds: 60))), isFalse);
  });

  test('Expires can establish freshness but missing freshness is always stale', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final expires = HttpCacheControlState.fromHeaders({
      'expires': received.add(const Duration(seconds: 60)).toHttpDate(),
    }, responseTime: received);
    expect(expires.canReuse(now: received.add(const Duration(seconds: 59))), isTrue);
    for (final headers in <Map<String, String>>[
      {},
      {'cache-control': 'must-revalidate'},
      {'cache-control': 's-maxage=600'},
      {'expires': 'not a date'},
      {'expires': 'Fri, xx Nov yyyy 10:20:30 GMT'},
    ]) {
      expect(HttpCacheControlState.fromHeaders(headers, responseTime: received).canReuse(now: received), isFalse);
    }
  });

  test('missing or malformed dates do not break explicit max-age', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    for (final date in [null, 'garbage', 'Fri, xx Nov yyyy 10:20:30 GMT']) {
      final state = HttpCacheControlState.fromHeaders({
        'Cache-Control': 'max-age=60',
        'Date': ?date,
      }, responseTime: received);
      expect(state.canReuse(now: received.add(const Duration(seconds: 59))), isTrue);
      expect(state.canReuse(now: received.add(const Duration(seconds: 60))), isFalse);
    }
  });

  test('no-cache and no-store prevent reuse even while fresh', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    for (final directive in ['no-cache', 'no-store', 'no-cache="Set-Cookie, X-Private"']) {
      final state = HttpCacheControlState.fromHeaders({
        'cache-control': 'max-age=600, must-revalidate, $directive',
      }, responseTime: received);
      expect(state.isFresh(now: received), isTrue);
      expect(state.canReuse(now: received), isFalse);
    }
  });

  test('quoted values are parsed and invalid or duplicate max-age is conservative', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final quoted = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age = "60", extension="a,b"',
    }, responseTime: received);
    expect(quoted.cacheControl.maxAge, 60);
    expect(quoted.canReuse(now: received), isTrue);
    for (final directive in ['max-age=60,max-age=120', 'max-age=-1', 'max-age=garbage', 'max-age']) {
      final state = HttpCacheControlState.fromHeaders({'cache-control': directive}, responseTime: received);
      expect(state.canReuse(now: received), isFalse);
    }
  });

  test('304 updates freshness without losing omitted policy or validators', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final state = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age=60',
      'date': received.toHttpDate(),
      'etag': '"first,variant"',
      'last-modified': received.subtract(const Duration(days: 1)).toHttpDate(),
    }, responseTime: received);
    final later = received.add(const Duration(minutes: 5));
    final refreshed = state.revalidated({'age': '10'}, requestTime: later, responseTime: later);
    expect(refreshed.etag, state.etag);
    expect(refreshed.lastModified, state.lastModified);
    expect(refreshed.cacheControl, state.cacheControl);
    expect(refreshed.canReuse(now: later.add(const Duration(seconds: 49))), isTrue);
    expect(refreshed.canReuse(now: later.add(const Duration(seconds: 50))), isFalse);
    expect(HttpCacheControlState.parseDataStr(refreshed.dataStr), refreshed);
  });

  test('old persisted metadata must validate once because it has no age information', () {
    final state = HttpCacheControlState.parseDataStr('2,600,null,1767323045,null,"v1",null');
    expect(state.etag, '"v1"');
    expect(state.canReuse(now: DateTime.utc(2026, 1, 2, 3, 4, 5)), isFalse);
  });

  test('corrupt metadata rejects invalid structure and negative stored age', () {
    expect(() => HttpCacheControlState.parseDataStr('[]'), throwsFormatException);
    expect(
      () => HttpCacheControlState.parseDataStr('[0,60,null,null,null,null,null,1767323045000,-1,false]'),
      throwsFormatException,
    );
  });

  test('Vary star prevents fresh reuse and request max-age can constrain reuse', () {
    final received = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final state = HttpCacheControlState.fromHeaders({'cache-control': 'max-age=600'}, responseTime: received);
    expect(state.canReuse(now: received.add(const Duration(seconds: 2)), maxAge: 1), isFalse);
    final vary = HttpCacheControlState.fromHeaders({
      'cache-control': 'max-age=600',
      'vary': '*',
    }, responseTime: received);
    expect(vary.canReuse(now: received), isFalse);
    expect(HttpCacheControlState.parseDataStr(vary.dataStr).varyAll, isTrue);
    final validated = vary.revalidated(
      {'cache-control': 'max-age=1200'},
      requestTime: received,
      responseTime: received,
    );
    expect(validated.canReuse(now: received), isFalse);
  });
}
