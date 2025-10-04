/// This is a workaround for WASM+Safari StringBuffer issue. For native code, use StringBuffer directly.
typedef StringBufferWrapper = StringBuffer;

/// This is a workaround for WASM+Safari StringBuffer issue (#483).
///
/// - for native code, use [StringBuffer] directly
/// - for Flutter Web, use this [StringBufferWrapper] that internally uses [String] instead.
StringBufferWrapper createStringBufferForWorkaroundSafariWasm() => StringBuffer();
