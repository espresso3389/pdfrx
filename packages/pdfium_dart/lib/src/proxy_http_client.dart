import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef HttpClientFactory = Future<http.Client> Function();

const _downloadRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// Creates an HTTP client using environment proxies and static OS proxy settings.
Future<http.Client> createProxyAwareHttpClient() async {
  final systemProxyEnvironment = Platform.isWindows
      ? loadWindowsProxyEnvironment()
      : Platform.isMacOS
      ? await _loadMacOSProxyEnvironment()
      : null;
  final client = HttpClient()
    ..findProxy = (url) =>
        findDownloadProxy(url, Platform.environment, systemProxyEnvironment);
  return IOClient(client);
}

/// Resolves explicit environment settings before falling back to the OS settings.
String findDownloadProxy(
  Uri url,
  Map<String, String> environment,
  Map<String, String>? systemEnvironment,
) {
  if (_hasProxyForScheme(environment, url.scheme) ||
      systemEnvironment == null) {
    return HttpClient.findProxyFromEnvironment(url, environment: environment);
  }
  final bypass = systemEnvironment['no_proxy'] ?? '';
  for (final entry in bypass.split(',')) {
    if (entry == '<local>' &&
        !url.host.contains('.') &&
        !url.host.contains(':'))
      return 'DIRECT';
    if (entry.contains('*')) {
      final pattern = entry.split('*').map(RegExp.escape).join('.*');
      if (RegExp('^$pattern\$', caseSensitive: false).hasMatch(url.host))
        return 'DIRECT';
    }
  }
  return HttpClient.findProxyFromEnvironment(
    url,
    environment: {
      ...systemEnvironment,
      'no_proxy': [
        bypass,
        environment['no_proxy'] ?? environment['NO_PROXY'] ?? '',
      ].join(','),
    },
  );
}

/// Gets [uri], retrying transient network and server failures with a fresh client.
Future<http.Response> getWithRetries(
  Uri uri, {
  HttpClientFactory clientFactory = createProxyAwareHttpClient,
  List<Duration> retryDelays = _downloadRetryDelays,
}) async {
  for (var attempt = 0; ; attempt++) {
    final client = await clientFactory();
    try {
      final response = await client.get(uri);
      if (!_isTransientStatus(response.statusCode) ||
          attempt == retryDelays.length) {
        return response;
      }
      stderr.writeln(
        'PDFium download returned HTTP ${response.statusCode}; retrying in ${retryDelays[attempt].inSeconds}s.',
      );
    } on http.ClientException catch (error) {
      if (attempt == retryDelays.length) rethrow;
      stderr.writeln(
        'PDFium download failed ($error); retrying in ${retryDelays[attempt].inSeconds}s.',
      );
    } on SocketException catch (error) {
      if (attempt == retryDelays.length) rethrow;
      stderr.writeln(
        'PDFium download failed ($error); retrying in ${retryDelays[attempt].inSeconds}s.',
      );
    } finally {
      client.close();
    }
    await Future<void>.delayed(retryDelays[attempt]);
  }
}

bool _isTransientStatus(int statusCode) =>
    statusCode == HttpStatus.requestTimeout ||
    statusCode == HttpStatus.tooManyRequests ||
    statusCode >= HttpStatus.internalServerError;

bool _hasProxyForScheme(Map<String, String> environment, String scheme) {
  return environment.containsKey('${scheme.toLowerCase()}_proxy') ||
      environment.containsKey('${scheme.toUpperCase()}_PROXY');
}

/// The layout of WINHTTP_CURRENT_USER_IE_PROXY_CONFIG from winhttp.h.
final class _WindowsProxyConfig extends Struct {
  @Int32()
  external int autoDetect;
  external Pointer<Utf16> autoConfigUrl;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> proxyBypass;
}

/// Reads the current user's static proxy for the active Windows connection.
Map<String, String>? loadWindowsProxyEnvironment() {
  final getConfig = DynamicLibrary.open('winhttp.dll')
      .lookupFunction<
        Int32 Function(Pointer<_WindowsProxyConfig>),
        int Function(Pointer<_WindowsProxyConfig>)
      >('WinHttpGetIEProxyConfigForCurrentUser');
  final globalFree = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalFree');
  final config = calloc<_WindowsProxyConfig>();
  try {
    if (getConfig(config) == 0) return null;
    return parseWindowsProxySettings(
      config.ref.proxy == nullptr ? null : config.ref.proxy.toDartString(),
      config.ref.proxyBypass == nullptr
          ? null
          : config.ref.proxyBypass.toDartString(),
    );
  } finally {
    for (final value in [
      config.ref.autoConfigUrl,
      config.ref.proxy,
      config.ref.proxyBypass,
    ]) {
      if (value != nullptr) globalFree(value.cast());
    }
    calloc.free(config);
  }
}

/// Converts static Windows proxy and bypass strings into HTTP client settings.
Map<String, String>? parseWindowsProxySettings(
  String? proxyServer, [
  String? proxyOverride,
]) {
  if (proxyServer == null || proxyServer.trim().isEmpty) return null;
  proxyServer = proxyServer.trim();
  final environment = <String, String>{};
  if (!proxyServer.contains('=')) {
    environment['http_proxy'] = proxyServer;
    environment['https_proxy'] = proxyServer;
  } else {
    for (final entry in proxyServer.split(';')) {
      final separator = entry.indexOf('=');
      if (separator <= 0 || separator == entry.length - 1) continue;
      final scheme = entry.substring(0, separator).trim().toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        environment['${scheme}_proxy'] = entry.substring(separator + 1).trim();
      }
    }
  }

  if (proxyOverride != null && proxyOverride.isNotEmpty) {
    final bypass = proxyOverride
        .split(';')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    environment['no_proxy'] = bypass.join(',');
  }
  return environment.isEmpty ? null : environment;
}

Future<Map<String, String>?> _loadMacOSProxyEnvironment() async {
  try {
    final result = await Process.run('/usr/sbin/scutil', ['--proxy']);
    if (result.exitCode != 0) return null;
    return parseMacOSProxySettings(result.stdout as String);
  } on ProcessException {
    return null;
  }
}

/// Parses global static proxies and exceptions from `scutil --proxy` output.
Map<String, String>? parseMacOSProxySettings(String output) {
  final values = <String, String>{};
  final exceptions = <String>[];
  var depth = 0;
  var inExceptions = false;
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.endsWith('{')) {
      if (depth == 1 && line.startsWith('ExceptionsList :'))
        inExceptions = true;
      depth++;
      continue;
    }
    if (line == '}') {
      if (depth == 2) inExceptions = false;
      depth--;
      continue;
    }
    final match = RegExp(r'^(\S+)\s*:\s*(.*?)\s*$').firstMatch(line);
    if (match == null) continue;
    if (depth == 1) values[match[1]!] = match[2]!;
    if (depth == 2 && inExceptions) exceptions.add(match[2]!);
  }
  final environment = <String, String>{};
  for (final scheme in ['HTTP', 'HTTPS']) {
    if (values['${scheme}Enable'] != '1') continue;
    final host = values['${scheme}Proxy'];
    final port = int.tryParse(values['${scheme}Port'] ?? '');
    if (host == null ||
        host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535)
      continue;
    final authority = host.contains(':') && !host.startsWith('[')
        ? '[$host]'
        : host;
    environment['${scheme.toLowerCase()}_proxy'] = '$authority:$port';
  }
  if (environment.isEmpty) return null;
  if (values['ExcludeSimpleHostnames'] == '1') exceptions.add('<local>');
  if (exceptions.isNotEmpty) environment['no_proxy'] = exceptions.join(',');
  return environment;
}
