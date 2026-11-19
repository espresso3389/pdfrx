import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// HTTP cache control states for a private cache.
class HttpCacheControlState {
  const HttpCacheControlState({
    required this.cacheControl,
    this.date,
    this.expires,
    this.etag,
    this.lastModified,
    this.responseTime,
    this.initialAge = Duration.zero,
    this.varyAll = false,
  });

  static const empty = HttpCacheControlState(cacheControl: HttpCacheControl(directives: 0));

  /// [maxAgeForNoStore] converts `no-store` to `no-cache` with [maxAgeForNoStore].
  static HttpCacheControlState fromHeaders(
    Map<String, String> headers, {
    Duration? maxAgeForNoStore,
    DateTime? requestTime,
    DateTime? responseTime,
  }) {
    final normalized = {for (final entry in headers.entries) entry.key.toLowerCase(): entry.value};
    final directives = _parseDirectives(normalized['cache-control']);
    responseTime ??= DateTime.now();
    requestTime ??= responseTime;
    final date =
        _parseHttpDateTime(normalized['date']) ??
        DateTime.fromMillisecondsSinceEpoch(responseTime.secondsSinceEpoch * 1000, isUtc: true);
    var noCache =
        directives.containsKey('no-cache') ||
        (normalized['cache-control'] == null && normalized['pragma']?.toLowerCase().trim() == 'no-cache');
    var noStore = directives.containsKey('no-store');
    var maxAge = _directiveSeconds(directives, 'max-age');
    if (noStore && maxAgeForNoStore != null) {
      noCache = true;
      noStore = false;
      maxAge = maxAgeForNoStore.inSeconds;
    }
    final apparentAge = max(0, responseTime.difference(date).inMilliseconds);
    final responseDelay = max(0, responseTime.difference(requestTime).inMilliseconds);
    final age = _deltaSeconds(normalized['age']?.split(',').first.trim()) ?? 0;
    return HttpCacheControlState(
      cacheControl: HttpCacheControl.fromDirectives(
        noCache: noCache,
        mustRevalidate: directives.containsKey('must-revalidate'),
        noStore: noStore,
        private: directives.containsKey('private'),
        public: directives.containsKey('public'),
        mustUnderstand: directives.containsKey('must-understand'),
        noTransform: directives.containsKey('no-transform'),
        immutable: directives.containsKey('immutable'),
        staleWhileRevalidate: directives.containsKey('stale-while-revalidate'),
        staleIfError: directives.containsKey('stale-if-error'),
        maxAge: maxAge,
        sMaxAge: _directiveSeconds(directives, 's-maxage'),
      ),
      date: date,
      expires: _parseHttpDateTime(normalized['expires']),
      etag: normalized['etag'],
      lastModified: _parseHttpDateTime(normalized['last-modified']),
      responseTime: responseTime,
      initialAge: Duration(milliseconds: max(apparentAge, age * 1000 + responseDelay)),
      varyAll: normalized['vary']?.split(',').any((name) => name.trim() == '*') == true,
    );
  }

  final HttpCacheControl cacheControl;
  final DateTime? date;
  final DateTime? expires;
  final String? etag;
  final DateTime? lastModified;

  /// Receipt time and corrected age at receipt, as defined by RFC 9111 section 4.2.3.
  final DateTime? responseTime;
  final Duration initialAge;
  final bool varyAll;

  Map<String, String> getHeadersForFetch() => {
    'If-None-Match': ?etag,
    if (etag == null && lastModified != null) 'If-Modified-Since': lastModified!.toHttpDate(),
  };

  /// Whether this response can be reused without contacting the origin.
  bool canReuse({required DateTime now, int? maxAge}) =>
      !cacheControl.noCache &&
      !cacheControl.noStore &&
      !varyAll &&
      isFresh(now: now) &&
      (maxAge == null || currentAge(now: now) < Duration(seconds: maxAge));

  /// Corrected age including time resident in this cache.
  Duration currentAge({required DateTime now}) =>
      initialAge + Duration(milliseconds: max(0, now.difference(responseTime ?? now).inMilliseconds));

  bool isFresh({required DateTime now}) {
    // Older cache metadata has no corrected age; validate it once before reuse.
    final received = responseTime;
    if (received == null || now.isBefore(received)) return false;
    final lifetime = cacheControl.maxAge != null
        ? Duration(seconds: cacheControl.maxAge!)
        : expires != null && date != null
        ? expires!.difference(date!)
        : Duration.zero;
    return currentAge(now: now) < lifetime;
  }

  bool isStale({required DateTime now}) => !isFresh(now: now);

  /// Merge only fields supplied by a successful validation response.
  HttpCacheControlState revalidated(
    Map<String, String> headers, {
    required DateTime requestTime,
    required DateTime responseTime,
  }) {
    final normalized = {for (final entry in headers.entries) entry.key.toLowerCase(): entry.value};
    return HttpCacheControlState.fromHeaders(
      {
        'cache-control': cacheControl.toString(),
        if (varyAll) 'vary': '*',
        if (expires != null) 'expires': expires!.toHttpDate(),
        'etag': ?etag,
        if (lastModified != null) 'last-modified': lastModified!.toHttpDate(),
        ...normalized,
      },
      requestTime: requestTime,
      responseTime: responseTime,
    );
  }

  String get dataStr => _encodeData(etag);

  /// Preserve freshness metadata if a validator exceeds the fixed disk header.
  String get dataStrWithoutEtag => _encodeData(null);

  String _encodeData(String? etag) => jsonEncode([
    cacheControl.directives,
    cacheControl.maxAge,
    cacheControl.sMaxAge,
    date?.secondsSinceEpoch,
    expires?.secondsSinceEpoch,
    etag,
    lastModified?.secondsSinceEpoch,
    responseTime?.millisecondsSinceEpoch,
    initialAge.inMilliseconds,
    varyAll,
  ]);

  static HttpCacheControlState parseDataStr(String dataStr) {
    if (dataStr.startsWith('[')) {
      final parts = jsonDecode(dataStr) as List<dynamic>;
      if (parts.length != 10 ||
          (parts[8] as int) < 0 ||
          (parts[1] != null && ((parts[1] as int) < 0 || (parts[1] as int) > 2147483648))) {
        throw const FormatException('Invalid cache metadata');
      }
      return HttpCacheControlState(
        cacheControl: HttpCacheControl(
          directives: parts[0] as int,
          maxAge: parts[1] as int?,
          sMaxAge: parts[2] as int?,
        ),
        date: _dateFromSeconds(parts[3] as int?),
        expires: _dateFromSeconds(parts[4] as int?),
        etag: parts[5] as String?,
        lastModified: _dateFromSeconds(parts[6] as int?),
        responseTime: parts[7] == null ? null : DateTime.fromMillisecondsSinceEpoch(parts[7] as int, isUtc: true),
        initialAge: Duration(milliseconds: parts[8] as int),
        varyAll: parts[9] as bool,
      );
    }
    // Legacy metadata remains readable, but cannot bypass revalidation.
    final parts = dataStr.split(',');
    if (parts.length < 7) throw const FormatException('Invalid cache metadata');
    return HttpCacheControlState(
      cacheControl: HttpCacheControl(
        directives: int.parse(parts[0]),
        maxAge: _parseInt(parts[1]),
        sMaxAge: _parseInt(parts[2]),
      ),
      date: _dateFromSeconds(_parseInt(parts[3])),
      expires: _dateFromSeconds(_parseInt(parts[4])),
      etag: parts[5] != 'null' ? parts.sublist(5, parts.length - 1).join(',') : null,
      lastModified: _dateFromSeconds(_parseInt(parts.last)),
    );
  }

  @override
  String toString() =>
      'HttpCacheControlState{cacheControl: "$cacheControl", date: $date, '
      'expires: $expires, etag: $etag, lastModified: $lastModified, responseTime: $responseTime, initialAge: $initialAge}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpCacheControlState &&
          runtimeType == other.runtimeType &&
          cacheControl == other.cacheControl &&
          date == other.date &&
          expires == other.expires &&
          etag == other.etag &&
          lastModified == other.lastModified &&
          responseTime == other.responseTime &&
          initialAge == other.initialAge &&
          varyAll == other.varyAll;

  @override
  int get hashCode => Object.hash(cacheControl, date, expires, etag, lastModified, responseTime, initialAge, varyAll);
}

Map<String, List<String?>> _parseDirectives(String? value) {
  final result = <String, List<String?>>{};
  if (value == null) return result;
  // Commas inside quoted field-name lists belong to that directive's value.
  final tokens = RegExp(r'(?:[^,"]|"(?:[^"\\]|\\.)*")+').allMatches(value);
  for (final token in tokens) {
    final parts = token.group(0)!.split('=');
    final name = parts.first.trim().toLowerCase();
    final value = parts.length > 1 ? parts.sublist(1).join('=').trim() : null;
    (result[name] ??= []).add(value);
  }
  return result;
}

int? _directiveSeconds(Map<String, List<String?>> directives, String name) {
  final values = directives[name];
  if (values == null) return null;
  // Duplicate or invalid freshness directives must not extend reuse.
  if (values.length != 1) return 0;
  var value = values.single;
  if (value != null && value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    value = value.substring(1, value.length - 1);
  }
  return _deltaSeconds(value) ?? 0;
}

int? _deltaSeconds(String? value) {
  if (value == null || !RegExp(r'^\d+$').hasMatch(value)) return null;
  return min(int.tryParse(value) ?? 2147483648, 2147483648);
}

int? _parseInt(String s) => s == 'null' ? null : int.parse(s);
DateTime? _dateFromSeconds(int? seconds) =>
    seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

DateTime? _parseHttpDateTime(String? value) {
  if (value == null) return null;
  try {
    return HttpDate.parse(value);
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

extension DateTimeHttpExtension on DateTime {
  /// Convert to HTTP date-time string.
  String toHttpDate() {
    // final _httpDateTimeFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss zzz', 'en_US');
    // '${_httpDateTimeFormat.format(toUtc())}GMT';
    final time = toUtc();
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '${_weekDays[time.weekday - 1]}, $day ${_months[time.month - 1]} ${time.year} $hour:$minute:$second GMT';
  }

  int get secondsSinceEpoch => millisecondsSinceEpoch ~/ 1000;
}

const _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
