/// A workaround for WASM+Safari StringBuffer issue.
class StringBufferWrapper {
  String buffer = '';

  void write(Object? str) {
    buffer += str?.toString() ?? '';
  }

  int get length => buffer.length;

  @override
  String toString() => buffer;
}

/// This is a workaround for WASM+Safari StringBuffer issue (#483).
///
/// - for native code, use [StringBuffer] directly
/// - for Flutter Web, use this [StringBufferWrapper] that internally uses [String] instead.
StringBufferWrapper createStringBufferForWorkaroundSafariWasm() => StringBufferWrapper();
