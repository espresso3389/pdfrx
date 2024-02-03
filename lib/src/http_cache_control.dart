import 'package:intl/intl.dart';

/// HTTP cache-control directives.
class HttpCacheControl {
  const HttpCacheControl({required this.directives, this.maxAge, this.sMaxAge});
  const HttpCacheControl.fromDirectives({
    bool noCache = false,
    bool mustRevalidate = false,
    bool noStore = false,
    bool private = false,
    bool public = false,
    bool mustUnderstand = false,
    bool noTransform = false,
    bool immutable = false,
    bool staleWhileRevalidate = false,
    bool staleIfError = false,
    this.maxAge,
    this.sMaxAge,
  }) : directives = (noCache ? _bitNoCache : 0) |
            (mustRevalidate ? _bitMustRevalidate : 0) |
            (noStore ? _bitNoStore : 0) |
            (private ? _bitPrivate : 0) |
            (public ? _bitPublic : 0) |
            (mustUnderstand ? _bitMustUnderstand : 0) |
            (noTransform ? _bitNoTransform : 0) |
            (immutable ? _bitImmutable : 0) |
            (staleWhileRevalidate ? _bitStaleWhileRevalidate : 0) |
            (staleIfError ? _bitStaleIfError : 0);

  final int directives;
  final int? maxAge;
  final int? sMaxAge;

  bool get noCache => (directives & _bitNoCache) != 0;
  bool get mustRevalidate => (directives & _bitMustRevalidate) != 0;
  bool get noStore => (directives & _bitNoStore) != 0;
  bool get private => (directives & _bitPrivate) != 0;
  bool get public => (directives & _bitPublic) != 0;
  bool get mustUnderstand => (directives & _bitMustUnderstand) != 0;
  bool get noTransform => (directives & _bitNoTransform) != 0;
  bool get immutable => (directives & _bitImmutable) != 0;
  bool get staleWhileRevalidate => (directives & _bitStaleWhileRevalidate) != 0;
  bool get staleIfError => (directives & _bitStaleIfError) != 0;

  static const _bitNoCache = 1 << 0;
  static const _bitMustRevalidate = 1 << 1;
  static const _bitNoStore = 1 << 2;
  static const _bitPrivate = 1 << 3;
  static const _bitPublic = 1 << 4;
  static const _bitMustUnderstand = 1 << 5;
  static const _bitNoTransform = 1 << 6;
  static const _bitImmutable = 1 << 7;
  static const _bitStaleWhileRevalidate = 1 << 8;
  static const _bitStaleIfError = 1 << 9;

  @override
  String toString() {
    final sb = StringBuffer();
    if (noCache) sb.write('no-cache,');
    if (mustRevalidate) sb.write('must-revalidate,');
    if (noStore) sb.write('no-store,');
    if (private) sb.write('private,');
    if (public) sb.write('public,');
    if (mustUnderstand) sb.write('must-understand,');
    if (noTransform) sb.write('no-transform,');
    if (immutable) sb.write('immutable,');
    if (staleWhileRevalidate) sb.write('stale-while-revalidate,');
    if (staleIfError) sb.write('stale-if-error,');
    if (maxAge != null) sb.write('max-age=$maxAge,');
    if (sMaxAge != null) sb.write('s-maxage=$sMaxAge,');
    return sb.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpCacheControl &&
          runtimeType == other.runtimeType &&
          directives == other.directives &&
          maxAge == other.maxAge &&
          sMaxAge == other.sMaxAge;

  @override
  int get hashCode => directives.hashCode ^ maxAge.hashCode ^ sMaxAge.hashCode;
}

/// HTTP cache control states.
class HttpCacheControlState {
  const HttpCacheControlState(
      {required this.cacheControl,
      this.date,
      this.expires,
      this.etag,
      this.lastModified});

  static const empty =
      HttpCacheControlState(cacheControl: HttpCacheControl(directives: 0));

  /// [maxAgeForNoStore] to convert `no-store` directive to `no-cache` with `maxAge`.
  static HttpCacheControlState fromHeaders(
    Map<String, String> headers, {
    Duration? maxAgeForNoStore,
  }) {
    final cacheControl = headers['cache-control']?.split(',');
    final date = headers['date'] != null
        ? _httpDateTimeFormat.parseUtc(headers['date']!)
        : null;
    final expires = headers['expires'] != null
        ? _httpDateTimeFormat.parseUtc(headers['expires']!)
        : null;
    final etag = headers['etag'];
    final lastModified = headers['last-modified'] != null
        ? _httpDateTimeFormat.parseUtc(headers['last-modified']!)
        : null;
    var noCache = cacheControl?.contains('no-cache') == true;
    var noStore = cacheControl?.contains('no-store') == true;
    var maxAge = int.tryParse(cacheControl
            ?.firstWhere((e) => e.startsWith('max-age='),
                orElse: () => '********')
            .substring(8) ??
        '');
    if (noStore && maxAgeForNoStore != null) {
      noCache = true;
      noStore = false;
      maxAge = maxAgeForNoStore.inSeconds;
    }
    return HttpCacheControlState(
      cacheControl: cacheControl != null
          ? HttpCacheControl.fromDirectives(
              noCache: noCache,
              mustRevalidate: cacheControl.contains('must-revalidate'),
              noStore: noStore,
              private: cacheControl.contains('private'),
              public: cacheControl.contains('public'),
              mustUnderstand: cacheControl.contains('must-understand'),
              noTransform: cacheControl.contains('no-transform'),
              immutable: cacheControl.contains('immutable'),
              staleWhileRevalidate:
                  cacheControl.contains('stale-while-revalidate'),
              staleIfError: cacheControl.contains('stale-if-error'),
              maxAge: maxAge,
            )
          : const HttpCacheControl(directives: 0),
      date: date,
      expires: expires,
      etag: etag,
      lastModified: lastModified,
    );
  }

  final HttpCacheControl cacheControl;
  final DateTime? date;
  final DateTime? expires;
  final String? etag;
  final DateTime? lastModified;

  Map<String, String> getHeadersForFetch() {
    return {
      if (etag != null) 'If-None-Match': etag!,
      if (etag == null && lastModified != null)
        'If-Modified-Since': lastModified!.toHttpDate(),
    };
  }

  bool isFresh({required DateTime now}) {
    if (cacheControl.maxAge != null &&
        date != null &&
        date!.add(Duration(seconds: cacheControl.maxAge!)).isBefore(now)) {
      return false;
    }
    if (expires != null && expires!.isBefore(now)) return false;
    return true;
  }

  bool isStale({required DateTime now}) => !isFresh(now: now);

  String get dataStr {
    return '${cacheControl.directives},${cacheControl.maxAge},${cacheControl.sMaxAge},'
        '${date?.secondsSinceEpoch},${expires?.secondsSinceEpoch},$etag,${lastModified?.secondsSinceEpoch}';
  }

  static HttpCacheControlState parseDataStr(String dataStr) {
    final parts = dataStr.split(',');
    return HttpCacheControlState(
      cacheControl: HttpCacheControl(
        directives: int.parse(parts[0]),
        maxAge: _parseInt(parts[1]),
        sMaxAge: _parseInt(parts[2]),
      ),
      date: _parseDateTime(parts[3]),
      expires: _parseDateTime(parts[4]),
      etag: parts[5] != 'null' ? parts[5] : null,
      lastModified: _parseDateTime(parts[6]),
    );
  }

  @override
  String toString() {
    return 'HttpCacheControlState{cacheControl: "$cacheControl", date: $date, expires: $expires, etag: $etag, lastModified: $lastModified}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpCacheControlState &&
          runtimeType == other.runtimeType &&
          cacheControl == other.cacheControl &&
          date == other.date &&
          expires == other.expires &&
          etag == other.etag &&
          lastModified == other.lastModified;

  @override
  int get hashCode =>
      cacheControl.hashCode ^
      date.hashCode ^
      expires.hashCode ^
      etag.hashCode ^
      lastModified.hashCode;
}

int _parseInt(String s) => s == 'null' ? 0 : int.parse(s);

DateTime? _parseDateTime(String s) => s == 'null'
    ? null
    : DateTime.fromMillisecondsSinceEpoch(int.parse(s) * 1000);

final _httpDateTimeFormat =
    DateFormat('EEE, dd MMM yyyy HH:mm:ss zzz', 'en_US');

extension DateTimeHttpExtension on DateTime {
  String toHttpDate() => '${_httpDateTimeFormat.format(toUtc())}GMT';

  int get secondsSinceEpoch => millisecondsSinceEpoch ~/ 1000;
}
