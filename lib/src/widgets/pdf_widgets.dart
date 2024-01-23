import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../pdfrx.dart';

class PdfDocumentRefProvider extends StatefulWidget {
  const PdfDocumentRefProvider({
    required this.documentRef,
    super.key,
  });

  PdfDocumentRefProvider.asset(
    String assetName, {
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefAsset(
          assetName,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          autoDispose: autoDispose,
        );

  PdfDocumentRefProvider.file(
    String filePath, {
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefFile(
          filePath,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          autoDispose: autoDispose,
        );

  PdfDocumentRefProvider.data(
    Uint8List bytes, {
    required String sourceName,
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
    void Function()? onDispose,
  }) : documentRef = PdfDocumentRefData(bytes,
            sourceName: sourceName,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
            autoDispose: autoDispose,
            onDispose: onDispose);

  PdfDocumentRefProvider.uri(
    Uri uri, {
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefUri(
          uri,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          autoDispose: autoDispose,
        );

  PdfDocumentRefProvider.custom({
    required String sourceName,
    required int fileSize,
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    super.key,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
    bool autoDispose = true,
  }) : documentRef = PdfDocumentRefCustom(
          sourceName: sourceName,
          fileSize: fileSize,
          read: read,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
          onDispose: onDispose,
          autoDispose: autoDispose,
        );

  final PdfDocumentRef documentRef;

  @override
  State<PdfDocumentRefProvider> createState() => _PdfDocumentRefProviderState();
}

class _PdfDocumentRefProviderState extends State<PdfDocumentRefProvider>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
