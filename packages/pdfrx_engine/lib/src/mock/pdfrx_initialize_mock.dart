/// Mock implementation of pdfrxInitialize "that will never be supposed to be called."
///
/// Without this level of abstraction, pub.dev's analyzer will complain about the WASM incompatibility...
Future<void> pdfrxInitialize({String? tmpPath, String? pdfiumRelease}) async {
  throw UnimplementedError(
    'Wow, this is not supposed to be called.\n'
    'For WASM support, use Flutter and initialize with pdfrxFlutterInitialize function.',
  );
}
