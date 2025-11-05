/// PDF exception class.
class PdfException implements Exception {
  /// Creates a new [PdfException].
  const PdfException(this.message, [this.errorCode]);

  /// Exception message.
  final String message;

  /// Optional error code.
  final int? errorCode;
  @override
  String toString() => 'PdfException: $message';
}

/// PDF exception for password related errors.
class PdfPasswordException extends PdfException {
  /// Creates a new [PdfPasswordException].
  const PdfPasswordException(super.message);
}
