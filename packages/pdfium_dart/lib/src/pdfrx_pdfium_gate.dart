import 'dart:ffi';

const _gateAssetId = 'package:pdfium_dart/src/pdfrx_pdfium_gate.dart';

@Native<Void Function()>(
  symbol: 'pdfrx_pdfium_gate_enable',
  assetId: _gateAssetId,
)
external void _enable();

@Native<Int32 Function()>(
  symbol: 'pdfrx_pdfium_gate_is_enabled',
  assetId: _gateAssetId,
)
external int _isEnabled();

@Native<Void Function()>(
  symbol: 'pdfrx_pdfium_gate_acquire',
  assetId: _gateAssetId,
)
external void _acquire();

@Native<Void Function()>(
  symbol: 'pdfrx_pdfium_gate_release',
  assetId: _gateAssetId,
)
external void _release();

@Native<Int32 Function()>(
  symbol: 'pdfrx_pdfium_gate_claim_init',
  assetId: _gateAssetId,
)
external int _claimInit();

/// Process-wide native coordinator for PDFium.
///
/// Each Flutter engine has its own Dart isolates, but this library's statics
/// live in a single loaded module per OS process. Enable it from every engine
/// before initializing PDFium when using `desktop_multi_window`.
abstract final class PdfiumProcessGate {
  /// Turns on process-wide locking. Throws if the native gate library is missing.
  static void enable() {
    try {
      _enable();
    } on ArgumentError catch (error) {
      throw StateError(
        'The process-wide PDFium gate is enabled but the pdfrx_pdfium_gate '
        'native asset is missing: $error',
      );
    }
  }

  /// True when the native gate asset can be resolved in this isolate.
  static bool get isNativeAvailable {
    try {
      _isEnabled();
      return true;
    } on ArgumentError {
      return false;
    }
  }

  /// Waits until no other engine is inside a PDFium call.
  static void acquire() => _acquire();

  /// Allows another engine to enter PDFium.
  static void release() => _release();

  /// Caller must hold [acquire]. True for the first claim in this process.
  static bool claimInit() => _claimInit() != 0;
}
