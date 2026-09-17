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

  test('parses one Windows proxy for both HTTP schemes', () {
    final environment = parseWindowsProxySettings('''
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ       proxy.example.com:8080
    ProxyOverride  REG_SZ       localhost;127.0.0.1;<local>
''');

    expect(environment, {
      'http_proxy': 'proxy.example.com:8080',
      'https_proxy': 'proxy.example.com:8080',
      'no_proxy': 'localhost,127.0.0.1',
    });
  });

  test('parses per-scheme Windows proxies', () {
    final environment = parseWindowsProxySettings('''
    ProxyEnable  REG_DWORD  0x1
    ProxyServer  REG_SZ     http=proxy.example.com:80;https=secure.example.com:443;socks=socks.example.com:1080
''');

    expect(environment, {
      'http_proxy': 'proxy.example.com:80',
      'https_proxy': 'secure.example.com:443',
    });
  });

  test('ignores a disabled Windows proxy', () {
    expect(
      parseWindowsProxySettings('''
    ProxyEnable  REG_DWORD  0x0
    ProxyServer  REG_SZ     proxy.example.com:8080
'''),
      isNull,
    );
  });

  test('parses macOS HTTP and HTTPS proxies with bypass list', () {
    final environment = parseMacOSProxySettings('''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 8080
  HTTPProxy : proxy.example.com
  HTTPSEnable : 1
  HTTPSPort : 8443
  HTTPSProxy : secure.example.com
  ExceptionsList : <array> {
    localhost
    *.corp.example
  }
}
''');

    expect(environment, {
      'http_proxy': 'proxy.example.com:8080',
      'https_proxy': 'secure.example.com:8443',
      'no_proxy': 'localhost,*.corp.example',
    });
  });

  test('ignores a disabled macOS proxy', () {
    expect(
      parseMacOSProxySettings('''
<dictionary> {
  HTTPEnable : 0
  HTTPPort : 8080
  HTTPProxy : proxy.example.com
}
'''),
      isNull,
    );
  });

  test('ignores scoped macOS proxy dictionaries', () {
    final environment = parseMacOSProxySettings('''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 8080
  HTTPProxy : proxy.example.com
  __SCOPED__ : <dictionary> {
    en0 : <dictionary> {
      HTTPEnable : 0
      HTTPPort : 9999
      HTTPProxy : ignored.example.com
    }
  }
}
''');

    expect(environment, {'http_proxy': 'proxy.example.com:8080'});
  });

  test('formats IPv6 macOS proxy hosts without a port', () {
    final environment = parseMacOSProxySettings('''
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 2001:db8::10
}
''');

    expect(environment, {'http_proxy': '[2001:db8::10]'});
  });

  test('prefers explicit environment proxy over system proxy', () {
    expect(
      findProxyWithSystemFallback(
        Uri.parse('https://github.com/bblanchon/pdfium-binaries'),
        environment: {'https_proxy': 'env-proxy.example.com:9443'},
        systemProxyEnvironment: {
          'https_proxy': 'system-proxy.example.com:8443',
        },
      ),
      'PROXY env-proxy.example.com:9443',
    );
  });

  test('uses system proxy when environment proxy is absent', () {
    expect(
      findProxyWithSystemFallback(
        Uri.parse('https://github.com/bblanchon/pdfium-binaries'),
        environment: const {},
        systemProxyEnvironment: {
          'https_proxy': 'system-proxy.example.com:8443',
        },
      ),
      'PROXY system-proxy.example.com:8443',
    );
  });
}
