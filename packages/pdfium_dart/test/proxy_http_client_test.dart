import 'package:test/test.dart';

import '../hook/proxy_http_client.dart';

void main() {
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
}
