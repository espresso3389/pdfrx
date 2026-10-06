import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/link.dart' as link_hook;

const _darwinPdfiumProviderMetadataKey = 'darwin_pdfium_provider';
const _pdfiumFlutterXcframeworkProvider = 'pdfium_flutter_xcframework';
const _pdfiumAssetId = 'package:pdfium_dart/libpdfium';
const _gateAssetId = 'package:pdfium_dart/src/pdfrx_pdfium_gate.dart';

void main() {
  group('link hook', () {
    test('keeps PDFium native asset for macOS Flutter tests', () async {
      final input = _linkInput(
        targetOS: OS.macOS,
        pdfiumProvidedByFlutter: true,
      );
      final output = LinkOutputBuilder();

      await link_hook.linkPdfiumAssets(input, output);

      expect(_assetIds(output), contains(_pdfiumAssetId));
    });

    test('omits PDFium native asset for iOS Flutter apps', () async {
      final input = _linkInput(targetOS: OS.iOS, pdfiumProvidedByFlutter: true);
      final output = LinkOutputBuilder();

      await link_hook.linkPdfiumAssets(input, output);

      expect(_assetIds(output), isNot(contains(_pdfiumAssetId)));
    });

    test('keeps the process-wide PDFium gate asset for iOS Flutter apps', () async {
      final input = _linkInput(
        targetOS: OS.iOS,
        pdfiumProvidedByFlutter: true,
        extraAssets: [_gateAsset()],
      );
      final output = LinkOutputBuilder();

      await link_hook.linkPdfiumAssets(input, output);

      expect(_assetIds(output), contains(_gateAssetId));
      expect(_assetIds(output), isNot(contains(_pdfiumAssetId)));
    });
  });
}

LinkInput _linkInput({
  required OS targetOS,
  required bool pdfiumProvidedByFlutter,
  List<EncodedAsset> extraAssets = const [],
}) {
  final tempUri = Directory.systemTemp.uri;
  final builder = LinkInputBuilder()
    ..setupShared(
      packageRoot: Directory.current.uri,
      packageName: 'pdfium_dart',
      outputDirectoryShared: tempUri,
      outputFile: tempUri.resolve('pdfium_dart_link_output.json'),
    )
    ..setupLink(
      assets: [_pdfiumAsset(), ...extraAssets],
      assetsFromLinking: [
        if (pdfiumProvidedByFlutter)
          EncodedAsset('hooks/metadata', {
            'key': _darwinPdfiumProviderMetadataKey,
            'value': _pdfiumFlutterXcframeworkProvider,
          }),
      ],
      recordedUsesFile: null,
    );

  builder.addExtension(
    CodeAssetExtension(
      targetArchitecture: Architecture.current,
      targetOS: targetOS,
      linkModePreference: LinkModePreference.dynamic,
      iOS: targetOS == OS.iOS
          ? IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 17)
          : null,
      macOS: targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
    ),
  );
  return builder.build();
}

EncodedAsset _pdfiumAsset() {
  return CodeAsset(
    package: 'pdfium_dart',
    name: 'libpdfium',
    linkMode: DynamicLoadingBundled(),
    file: Directory.current.uri.resolve('test/pdfium_test.dart'),
  ).encode();
}

EncodedAsset _gateAsset() {
  return CodeAsset(
    package: 'pdfium_dart',
    name: 'src/pdfrx_pdfium_gate.dart',
    linkMode: DynamicLoadingBundled(),
    file: Directory.current.uri.resolve('src/pdfrx_pdfium_gate.c'),
  ).encode();
}

List<String> _assetIds(LinkOutputBuilder output) {
  return LinkOutput(output.json).assets.encodedAssets
      .where((asset) => asset.isCodeAsset)
      .map((asset) => CodeAsset.fromEncoded(asset).id)
      .toList();
}
