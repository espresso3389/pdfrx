import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'pdf_api.dart';

bool _isInitialized = false;

/// Explicitly initializes the Pdfrx library for Flutter.
///
/// This function actually sets up the following functions:
/// - [Pdfrx.loadAsset]: Loads an asset by name and returns its byte data.
/// - [Pdfrx.getCacheDirectory]: Returns the path to the temporary directory for caching.
void pdfrxFlutterInitialize() {
  if (_isInitialized) return;
  Pdfrx.loadAsset ??= (name) async {
    final asset = await rootBundle.load(name);
    return asset.buffer.asUint8List();
  };
  Pdfrx.getCacheDirectory ??= () async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  };

  _isInitialized = true;
}
