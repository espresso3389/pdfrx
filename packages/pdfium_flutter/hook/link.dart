import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _darwinPdfiumProviderMetadataKey = 'darwin_pdfium_provider';
const _pdfiumFlutterXcframeworkProvider = 'pdfium_flutter_xcframework';

void main(List<String> args) async {
  await link(args, (input, output) async {
    final targetOS = input.config.code.targetOS;
    if (targetOS == OS.iOS || targetOS == OS.macOS) {
      output.metadata.add(
        'pdfium_dart',
        _darwinPdfiumProviderMetadataKey,
        _pdfiumFlutterXcframeworkProvider,
      );
    }

    output.assets.addEncodedAssets(input.assets.encodedAssets);
  });
}
