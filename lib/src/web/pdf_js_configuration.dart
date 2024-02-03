/// Configuration for the PDF.js library.
///
/// Set [PdfJsConfiguration.configuration] before using any APIs. It can be typically set in the main function.
class PdfJsConfiguration {
  const PdfJsConfiguration({
    required this.pdfJsSrc,
    required this.workerSrc,
    required this.cMapUrl,
    required this.cMapPacked,
    this.pdfJsDownloadTimeout = const Duration(seconds: 10),
  });

  /// `psf.js` file URL such as https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.mjs
  final String pdfJsSrc;

  /// `psf.worker.js` file URL such as https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js
  final String workerSrc;

  /// `cmaps` directory URL such as https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/cmaps/
  final String cMapUrl;

  /// Whether to use the packed cmaps. Default is true.
  final bool cMapPacked;

  /// The timeout for downloading the PDF.js library. Default is 10 seconds.
  final Duration pdfJsDownloadTimeout;

  /// The current configuration. null to use the default.
  ///
  /// To customze the pdf.js download URLs, set this before using any APIs.:
  ///
  /// ```dart
  /// PdfJsConfiguration.configuration = const PdfJsConfiguration(
  ///   pdfJsSrc: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.mjs',
  ///   workerSrc: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js',
  ///   cMapUrl: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/cmaps/',
  /// );
  /// ```
  static PdfJsConfiguration? configuration;
}
