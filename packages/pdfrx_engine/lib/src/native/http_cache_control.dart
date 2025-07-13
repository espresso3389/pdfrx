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
  }) : directives =
           (noCache ? _bitNoCache : 0) |
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
    final sb = <String>[];
    if (noCache) sb.add('no-cache');
    if (mustRevalidate) sb.add('must-revalidate');
    if (noStore) sb.add('no-store');
    if (private) sb.add('private');
    if (public) sb.add('public');
    if (mustUnderstand) sb.add('must-understand');
    if (noTransform) sb.add('no-transform');
    if (immutable) sb.add('immutable');
    if (staleWhileRevalidate) sb.add('stale-while-revalidate');
    if (staleIfError) sb.add('stale-if-error');
    if (maxAge != null) sb.add('max-age=$maxAge');
    if (sMaxAge != null) sb.add('s-maxage=$sMaxAge');
    return sb.join(',');
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
  const HttpCacheControlState({required this.cacheControl, this.date, this.expires, this.etag, this.lastModified});

  static const empty = HttpCacheControlState(cacheControl: HttpCacheControl(directives: 0));

  /// [maxAgeForNoStore] to convert `no-store` directive to `no-cache` with `maxAge`.
  static HttpCacheControlState fromHeaders(Map<String, String> headers, {Duration? maxAgeForNoStore}) {
    final cacheControl = headers['cache-control']?.split(',');
    final date = _parseHttpDateTime(headers['date']);
    final expires = _parseHttpDateTime(headers['expires']);
    final etag = headers['etag'];
    final lastModified = _parseHttpDateTime(headers['last-modified']);
    var noCache = cacheControl?.contains('no-cache') ?? false;
    var noStore = cacheControl?.contains('no-store') ?? false;
    var maxAge = int.tryParse(
      cacheControl?.firstWhere((e) => e.startsWith('max-age='), orElse: () => '********').substring(8) ?? '',
    );
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
              staleWhileRevalidate: cacheControl.contains('stale-while-revalidate'),
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
      if (etag == null && lastModified != null) 'If-Modified-Since': lastModified!.toHttpDate(),
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
  int get hashCode => cacheControl.hashCode ^ date.hashCode ^ expires.hashCode ^ etag.hashCode ^ lastModified.hashCode;
}

int? _parseInt(String s) => s == 'null' ? null : int.parse(s);

DateTime? _parseDateTime(String s) => s == 'null' ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(s) * 1000);

/// Parse HTTP date-time string.
DateTime? _parseHttpDateTime(String? s) {
  if (s == null) return null;
  final parts = s.split(' ');
  if (parts.length != 6) return null;
  final day = int.parse(parts[1]);
  final month = _months.indexOf(parts[2]) + 1;
  final year = int.parse(parts[3]);
  final timeParts = parts[4].split(':');
  final hour = int.parse(timeParts[0]);
  final minute = int.parse(timeParts[1]);
  final second = int.parse(timeParts[2]);
  return DateTime.utc(year, month, day, hour, minute, second);
}

extension DateTimeHttpExtension on DateTime {
  /// Convert to HTTP date-time string.
  String toHttpDate() {
    // final _httpDateTimeFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss zzz', 'en_US');
    // '${_httpDateTimeFormat.format(toUtc())}GMT';
    final time = toUtc();
    return '${_weekDays[time.weekday - 1]}, ${time.day} ${_months[time.month - 1]} ${time.year} ${time.hour}:${time.minute}:${time.second} GMT';
  }

  int get secondsSinceEpoch => millisecondsSinceEpoch ~/ 1000;
}

const _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
