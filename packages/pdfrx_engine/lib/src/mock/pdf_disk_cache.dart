import '../pdf_disk_cache_policy.dart';

/// The native HTTP disk cache is not available on this platform.
Future<PdfDiskCacheStats> pdfrxTrimDiskCache({PdfDiskCachePolicy? policy}) =>
    Future.error(UnsupportedError('The native HTTP disk cache is not available on this platform'));
