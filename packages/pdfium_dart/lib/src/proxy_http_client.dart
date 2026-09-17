import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef HttpClientFactory = Future<http.Client> Function();

const _downloadRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// Creates an HTTP client that uses environment proxies and supported system proxy settings.
Future<http.Client> createProxyAwareHttpClient() async {
  final systemProxyEnvironment = await _loadSystemProxyEnvironment();
  final environment = Platform.environment;
  final client = HttpClient()
    ..findProxy = (url) => findProxyWithSystemFallback(
      url,
      environment: environment,
      systemProxyEnvironment: systemProxyEnvironment,
    );
  return IOClient(client);
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

/// Resolves a proxy directive for [url], preferring explicit environment proxies over system fallbacks.
String findProxyWithSystemFallback(
  Uri url, {
  required Map<String, String> environment,
  Map<String, String>? systemProxyEnvironment,
}) {
  final proxyFromEnvironment = HttpClient.findProxyFromEnvironment(
    url,
    environment: environment,
  );
  if (_hasProxyForScheme(environment, url.scheme) || systemProxyEnvironment == null) {
    return proxyFromEnvironment;
  }
  return HttpClient.findProxyFromEnvironment(
    url,
    environment: systemProxyEnvironment,
  );
}

Future<Map<String, String>?> _loadSystemProxyEnvironment() async {
  if (Platform.isWindows) return _loadWindowsProxyEnvironment();
  if (Platform.isMacOS) return _loadMacOSProxyEnvironment();
  return null;
}

Future<Map<String, String>?> _loadWindowsProxyEnvironment() async {
  try {
    final result = await Process.run('reg.exe', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]);
    if (result.exitCode != 0) return null;
    return parseWindowsProxySettings(result.stdout as String);
  } on ProcessException {
    return null;
  }
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

/// Converts static WinINet proxy registry values into the environment format understood by [HttpClient].
Map<String, String>? parseWindowsProxySettings(String registryOutput) {
  final values = <String, String>{};
  for (final line in registryOutput.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^\s*(\S+)\s+REG_\S+\s+(.+?)\s*$').firstMatch(line);
    if (match != null) values[match.group(1)!] = match.group(2)!;
  }
  if (values['ProxyEnable'] != '0x1') return null;

  final proxyServer = values['ProxyServer'];
  if (proxyServer == null || proxyServer.isEmpty) return null;
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

  final proxyOverride = values['ProxyOverride'];
  if (proxyOverride != null && proxyOverride.isNotEmpty) {
    final bypass = proxyOverride
        .split(';')
        .where((value) => value.isNotEmpty && value != '<local>');
    environment['no_proxy'] = bypass.join(',');
  }
  return environment.isEmpty ? null : environment;
}

/// Converts macOS `scutil --proxy` output into the environment format understood by [HttpClient].
Map<String, String>? parseMacOSProxySettings(String scutilOutput) {
  final values = <String, String>{};
  final bypass = <String>[];
  var currentArrayKey = '';
  var dictionaryDepth = 0;
  for (final rawLine in scutilOutput.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line == '<dictionary> {' || line == '{') {
      dictionaryDepth++;
      continue;
    }
    if (currentArrayKey.isNotEmpty) {
      if (line == '}') {
        currentArrayKey = '';
        dictionaryDepth--;
        continue;
      }
      if (dictionaryDepth == 2 && currentArrayKey == 'ExceptionsList') {
        bypass.add(line);
      }
      continue;
    }
    if (line.endsWith(': <dictionary> {')) {
      dictionaryDepth++;
      continue;
    }
    if (line == '}') {
      if (dictionaryDepth > 0) dictionaryDepth--;
      continue;
    }
    if (dictionaryDepth != 1) continue;

    final arrayMatch = RegExp(r'^(\S+)\s*:\s*<array>\s*\{$').firstMatch(line);
    if (arrayMatch != null) {
      currentArrayKey = arrayMatch.group(1)!;
      dictionaryDepth++;
      continue;
    }

    final match = RegExp(r'^(\S+)\s*:\s*(.+)$').firstMatch(line);
    if (match != null) values[match.group(1)!] = match.group(2)!.trim();
  }

  final environment = <String, String>{};
  _addMacOSProxy(environment, values, scheme: 'http', keyPrefix: 'HTTP');
  _addMacOSProxy(environment, values, scheme: 'https', keyPrefix: 'HTTPS');
  if (bypass.isNotEmpty) {
    environment['no_proxy'] = bypass.join(',');
  }
  return environment.isEmpty ? null : environment;
}

void _addMacOSProxy(
  Map<String, String> environment,
  Map<String, String> values, {
  required String scheme,
  required String keyPrefix,
}) {
  if (values['${keyPrefix}Enable'] != '1') return;
  final host = values['${keyPrefix}Proxy'];
  if (host == null || host.isEmpty) return;
  final port = values['${keyPrefix}Port'];
  environment['${scheme}_proxy'] = port == null || port.isEmpty ? host : '${_formatProxyHost(host)}:$port';
}

String _formatProxyHost(String host) {
  if (host.contains(':') && !host.startsWith('[') && !host.endsWith(']')) {
    return '[$host]';
  }
  return host;
}
