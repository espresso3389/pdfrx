import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:pdfium_dart/src/pdfium_downloader.dart' show PDFiumDownloader;

String libraryName = 'src/pdfium_bindings.g.dart';
void main(List<String> args) async {
  await build(args, (input, output) async {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: libraryName,
        linkMode: DynamicLoadingBundled(),
        file: await PDFiumDownloader.downloadAndGetPDFiumModulePath(
          input.outputDirectory.path,
          os: input.config.code.targetOS,
          arch: input.config.code.targetArchitecture,
        ),
      ),
    );
  });
}
