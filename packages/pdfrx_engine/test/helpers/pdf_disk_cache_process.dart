import 'dart:convert';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';

/// Separate OS process for testing lease ownership and crash recovery.
Future<void> main(List<String> args) async {
  Pdfrx.cacheDirectoryPath = args[0];
  final cache = await PdfFileCache.fromUri(Uri.parse(args[1]));
  cache.setBlockSize(4);
  await cache.initializeWithFileSize(8, truncateExistingContent: true);
  await cache.write(0, [1, 2, 3, 4, 5, 6, 7, 8]);
  await cache.setCached(0, lastBlock: 1);
  stdout.writeln(cache.file.path);
  await stdout.flush();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await cache.close();
}
