import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates an HTTP client that uses environment proxies and, on Windows, the user's static system proxy.
Future<http.Client> createProxyAwareHttpClient() async {
  final systemProxyEnvironment = Platform.isWindows
      ? await _loadWindowsProxyEnvironment()
      : null;
  final environment = Platform.environment;
  final client = HttpClient()
    ..findProxy = (url) {
      final proxyFromEnvironment = HttpClient.findProxyFromEnvironment(
        url,
        environment: environment,
      );
      if (_hasProxyForScheme(environment, url.scheme))
        return proxyFromEnvironment;
      if (systemProxyEnvironment != null) {
        return HttpClient.findProxyFromEnvironment(
          url,
          environment: systemProxyEnvironment,
        );
      }
      return proxyFromEnvironment;
    };
  return IOClient(client);
}

bool _hasProxyForScheme(Map<String, String> environment, String scheme) {
  return environment.containsKey('${scheme.toLowerCase()}_proxy') ||
      environment.containsKey('${scheme.toUpperCase()}_PROXY');
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
