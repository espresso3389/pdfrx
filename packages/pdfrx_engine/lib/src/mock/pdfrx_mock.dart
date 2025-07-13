import 'dart:async';
import 'dart:typed_data';

import '../../pdfrx_engine.dart';

/// This is an empty implementation of [PdfDocumentFactory] that just throws [UnimplementedError].
///
/// This is used to indicate that the factory is not initialized.
class PdfDocumentFactoryImpl implements PdfDocumentFactory {
  PdfDocumentFactoryImpl();

  Future<PdfDocument> unimplemented() {
    throw UnimplementedError(
      'PdfDocumentFactory.instance is not initialized. '
      'Please call pdfrxFlutterInitialize() or explicitly set PdfDocumentFactory.instance.',
    );
  }

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => unimplemented();

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) => unimplemented();

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    void Function()? onDispose,
  }) => unimplemented();

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => unimplemented();

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) => unimplemented();
}
