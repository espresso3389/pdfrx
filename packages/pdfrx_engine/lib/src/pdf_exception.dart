class PdfException implements Exception {
  const PdfException(this.message, [this.errorCode]);
  final String message;
  final int? errorCode;
  @override
  String toString() => 'PdfException: $message';
}

class PdfPasswordException extends PdfException {
  const PdfPasswordException(super.message);
}
