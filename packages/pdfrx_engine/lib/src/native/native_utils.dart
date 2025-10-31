import 'dart:io';

import 'package:path/path.dart' as path;

import '../pdfrx.dart';

/// Helper function to get the cache directory for a specific purpose and name.
Future<Directory> getCacheDirectory(
  String part1, [
  String? part2,
  String? part3,
  String? part4,
  String? part5,
  String? part6,
  String? part7,
  String? part8,
  String? part9,
  String? part10,
  String? part11,
  String? part12,
  String? part13,
  String? part14,
  String? part15,
]) async {
  if (Pdfrx.getCacheDirectory == null) {
    throw StateError('Pdfrx.getCacheDirectory is not set. Please set it to get cache directory.');
  }
  final dir = Directory(
    path.join(
      await Pdfrx.getCacheDirectory!(),
      part1,
      part2,
      part3,
      part4,
      part5,
      part6,
      part7,
      part8,
      part9,
      part10,
      part11,
      part12,
      part13,
      part14,
      part15,
    ),
  );
  await dir.create(recursive: true);
  return dir;
}
