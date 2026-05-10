import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _darwinPdfiumProviderMetadataKey = 'darwin_pdfium_provider';
const _pdfiumFlutterXcframeworkProvider = 'pdfium_flutter_xcframework';
const _pdfiumAssetId = 'package:pdfium_dart/libpdfium';

void main(List<String> args) async {
  await link(args, linkPdfiumAssets);
}

Future<void> linkPdfiumAssets(LinkInput input, LinkOutputBuilder output) async {
  if (!input.config.buildCodeAssets) {
    output.assets.addEncodedAssets(input.assets.encodedAssets);
    return;
  }

  final targetOS = input.config.code.targetOS;
  final pdfiumProvidedByFlutter =
      input.metadata[_darwinPdfiumProviderMetadataKey] ==
      _pdfiumFlutterXcframeworkProvider;
  // On macOS, PDFium is linked into the app by the XCFramework, but Flutter tests still need to load the PDFium asset
  // directly. Therefore we omit the PDFium asset only for iOS when provided by Flutter, but include it for macOS.
  final shouldOmitDarwinPdfiumAsset =
      pdfiumProvidedByFlutter && targetOS == OS.iOS;

  for (final asset in input.assets.encodedAssets) {
    final isPdfiumAsset =
        asset.isCodeAsset && CodeAsset.fromEncoded(asset).id == _pdfiumAssetId;
    if (shouldOmitDarwinPdfiumAsset && isPdfiumAsset) continue;

    output.assets.addEncodedAsset(asset);
  }
}
