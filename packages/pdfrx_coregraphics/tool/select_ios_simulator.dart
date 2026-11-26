import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final result = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    'available',
    '--json',
  ]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  final devices =
      jsonDecode(result.stdout as String)['devices'] as Map<String, dynamic>;
  for (final entry in devices.entries) {
    if (!entry.key.contains('iOS')) continue;
    for (final device in entry.value as List) {
      if ((device['name'] as String).startsWith('iPhone')) {
        stdout.writeln(device['udid']);
        return;
      }
    }
  }
  throw StateError('No available iPhone simulator');
}
