import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/src/proxy_http_client.dart';

void main() {
  test('retries a transient client failure', () async {
    var attempts = 0;
    final response = await getWithRetries(
      Uri.parse('https://example.com/pdfium.tgz'),
      clientFactory: () async => MockClient((request) async {
        attempts++;
        if (attempts == 1)
          throw http.ClientException('connection reset', request.url);
        return http.Response('archive', HttpStatus.ok);
      }),
      retryDelays: [Duration.zero],
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(attempts, 2);
  });

  test('retries a transient HTTP response', () async {
    var attempts = 0;
    final response = await getWithRetries(
      Uri.parse('https://example.com/pdfium.tgz'),
      clientFactory: () async => MockClient((request) async {
        attempts++;
        return http.Response(
          '',
          attempts == 1 ? HttpStatus.serviceUnavailable : HttpStatus.ok,
        );
      }),
      retryDelays: [Duration.zero],
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(attempts, 2);
  });

  test('does not retry a permanent HTTP response', () async {
    var attempts = 0;
    final response = await getWithRetries(
      Uri.parse('https://example.com/pdfium.tgz'),
      clientFactory: () async => MockClient((request) async {
        attempts++;
        return http.Response('', HttpStatus.notFound);
      }),
      retryDelays: [Duration.zero],
    );

    expect(response.statusCode, HttpStatus.notFound);
    expect(attempts, 1);
  });

  final direct = Uri.parse(
    'https://github.com/bblanchon/pdfium-binaries/releases/download/'
    'chromium%2F8125/pdfium-linux-x64.tgz',
  );
  final releaseApi = Uri.parse(
    'https://api.github.com/repos/bblanchon/pdfium-binaries/releases/tags/'
    'chromium%2F8125',
  );
  const assetApi =
      'https://api.github.com/repos/bblanchon/pdfium-binaries/'
      'releases/assets/123456789';

  test('returns original PDFium binary without calling the API', () async {
    final visited = <Uri>[];
    final result = await getPdfiumArchiveWithApiFallback(
      direct,
      clientFactory: () async => MockClient((request) async {
        visited.add(request.url);
        return http.Response.bytes([0x1f, 0x8b, 1], HttpStatus.ok);
      }),
      retryDelays: [],
    );
    expect(result.statusCode, HttpStatus.ok);
    expect(visited, [direct]);
  });

  test('recovers a 504 through the pinned GitHub release asset API', () async {
    final visited = <Uri>[];
    final result = await getPdfiumArchiveWithApiFallback(
      direct,
      clientFactory: () async => MockClient((request) async {
        visited.add(request.url);
        if (request.url == direct) {
          return http.Response('gateway timeout', HttpStatus.gatewayTimeout);
        }
        if (request.url == releaseApi) {
          expect(request.headers['accept'], 'application/vnd.github+json');
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'unrelated.tgz', 'url': assetApi},
                {'name': 'pdfium-linux-x64.tgz', 'url': assetApi},
              ],
            }),
            HttpStatus.ok,
          );
        }
        if (request.url.toString() == assetApi) {
          expect(request.headers['accept'], 'application/octet-stream');
          return http.Response.bytes([0x1f, 0x8b, 0, 7], HttpStatus.ok);
        }
        throw StateError('Unexpected API request ${request.url}');
      }),
      retryDelays: [],
    );
    expect(result.bodyBytes, [0x1f, 0x8b, 0, 7]);
    expect(visited, [direct, releaseApi, Uri.parse(assetApi)]);
  });

  test('refuses an untrusted release asset URL', () async {
    final visited = <Uri>[];
    final result = await getPdfiumArchiveWithApiFallback(
      direct,
      clientFactory: () async => MockClient((request) async {
        visited.add(request.url);
        if (request.url == direct) {
          return http.Response('gateway timeout', HttpStatus.gatewayTimeout);
        }
        return http.Response(
          jsonEncode({
            'assets': [
              {
                'name': 'pdfium-linux-x64.tgz',
                'url': 'https://example.invalid/evil.tgz',
              },
            ],
          }),
          HttpStatus.ok,
        );
      }),
      retryDelays: [],
    );
    expect(result.statusCode, HttpStatus.gatewayTimeout);
    expect(visited, [direct, releaseApi]);
  });

  test('does not accept JSON instead of an archive', () async {
    final result = await getPdfiumArchiveWithApiFallback(
      direct,
      clientFactory: () async => MockClient((request) async {
        if (request.url == direct) {
          return http.Response('gateway timeout', HttpStatus.gatewayTimeout);
        }
        if (request.url == releaseApi) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'pdfium-linux-x64.tgz', 'url': assetApi},
              ],
            }),
            HttpStatus.ok,
          );
        }
        return http.Response('{"id":123456789}', HttpStatus.ok);
      }),
      retryDelays: [],
    );
    expect(result.statusCode, HttpStatus.gatewayTimeout);
  });

  test('parses Windows proxy strings from the API', () {
    expect(parseWindowsProxySettings('proxy:8080', 'localhost;<local>'), {
      'http_proxy': 'proxy:8080',
      'https_proxy': 'proxy:8080',
      'no_proxy': 'localhost,<local>',
    });
    expect(
      parseWindowsProxySettings(
        'http=proxy:80;https=secure:443;socks=socks:1080',
      ),
      {'http_proxy': 'proxy:80', 'https_proxy': 'secure:443'},
    );
    expect(parseWindowsProxySettings(null), isNull);
    expect(parseWindowsProxySettings(''), isNull);
    expect(parseWindowsProxySettings('socks=socks:1080'), isNull);
  });

  test(
    'reads Windows configuration using the real ABI and allocator',
    () async {
      for (var i = 0; i < 10; i++) {
        loadWindowsProxyEnvironment();
      }
      final client = await createProxyAwareHttpClient();
      client.close();
    },
    skip: !Platform.isWindows,
  );

  test('parses global macOS settings and ignores scoped dictionaries', () {
    final settings = parseMacOSProxySettings(macOSSettings);
    expect(settings, {
      'http_proxy': 'proxy:8080',
      'https_proxy': '[::1]:8443',
      'no_proxy': '*.example.org,localhost,<local>',
    });
    expect(
      findDownloadProxy(Uri.parse('https://github.com'), {}, settings),
      'PROXY [::1]:8443',
    );
    expect(
      findDownloadProxy(Uri.parse('http://a.example.org'), {}, settings),
      'DIRECT',
    );
    expect(
      findDownloadProxy(Uri.parse('http://intranet'), {}, settings),
      'DIRECT',
    );
  });

  test('ignores disabled, invalid and PAC-only macOS settings', () {
    for (final fields in [
      'HTTPEnable : 0\nHTTPProxy : proxy\nHTTPPort : 8080',
      'HTTPEnable : 1\nHTTPProxy : proxy\nHTTPPort : 65536',
      'HTTPEnable : 1\nHTTPProxy : proxy\nHTTPPort : invalid',
      'HTTPEnable : 1\nHTTPPort : 8080',
      'ProxyAutoConfigEnable : 1\nProxyAutoConfigURLString : https://example.com/proxy.pac',
    ]) {
      expect(parseMacOSProxySettings('<dictionary> {\n$fields\n}'), isNull);
    }
    expect(parseMacOSProxySettings(''), isNull);
  });

  test('environment precedence and bypasses survive system fallback', () {
    final system = parseWindowsProxySettings(
      'proxy:8080',
      '*.internal;<local>',
    )!;
    final url = Uri.parse('https://github.com');
    for (final key in ['https_proxy', 'HTTPS_PROXY']) {
      expect(
        findDownloadProxy(url, {key: 'explicit:1234'}, system),
        'PROXY explicit:1234',
      );
      expect(findDownloadProxy(url, {key: ''}, system), 'DIRECT');
    }
    for (final key in ['no_proxy', 'NO_PROXY']) {
      expect(findDownloadProxy(url, {key: 'github.com'}, system), 'DIRECT');
    }
    expect(
      findDownloadProxy(url, {'http_proxy': 'explicit:1234'}, system),
      'PROXY proxy:8080',
    );
    expect(
      findDownloadProxy(Uri.parse('http://a.internal'), {}, system),
      'DIRECT',
    );
    expect(
      findDownloadProxy(Uri.parse('http://intranet'), {}, system),
      'DIRECT',
    );
    expect(findDownloadProxy(url, {}, null), 'DIRECT');
  });
}

const macOSSettings = '''
<dictionary> {
  ExceptionsList : <array> {
    0 : *.example.org
    1 : localhost
  }
  ExcludeSimpleHostnames : 1
  HTTPEnable : 1
  HTTPProxy : proxy
  HTTPPort : 8080
  HTTPSEnable : 1
  HTTPSProxy : ::1
  HTTPSPort : 8443
  __SCOPED__ : <dictionary> {
    en0 : <dictionary> {
      HTTPEnable : 1
      HTTPProxy : scoped.example.com
      HTTPPort : 9999
    }
  }
}
''';
