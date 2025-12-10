import 'dart:io';

import 'package:code_assets/code_assets.dart' show Architecture, OS;
import 'package:ffigen/ffigen.dart';
import 'package:pdfium_dart/src/pdfium_downloader.dart'
    show currentPDFiumRelease, PDFiumDownloader;

import '../hook/build.dart' show libraryName;

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  final modulePath = await getPdfium(
    cacheRootPath: packageRoot.resolve('tool/.tmp/').path,
  );
  FfiGenerator(
    output: Output(
      dartFile: packageRoot.resolve('lib/').resolve(libraryName),
      style: NativeExternalBindings(),
      commentType: CommentType(CommentStyle.any, CommentLength.full),
      preamble: '// ignore_for_file: unused_field, unused_element',
      format: true,
    ),
    enums: Enums.includeAll,
    globals: Globals.includeAll,
    functions: Functions.includeAll,
    structs: Structs.includeAll,
    macros: Macros.includeAll,
    typedefs: Typedefs.includeAll,
    headers: Headers(
      entryPoints: [
        'fpdf_signature.h',
        'fpdf_sysfontinfo.h',
        'fpdf_javascript.h',
        'fpdf_text.h',
        'fpdf_searchex.h',
        'fpdf_progressive.h',
        'fpdfview.h',
        'fpdf_edit.h',
        'fpdf_attachment.h',
        'fpdf_annot.h',
        'fpdf_catalog.h',
        'fpdf_ppo.h',
        'fpdf_formfill.h',
        'fpdf_save.h',
        'fpdf_doc.h',
        'fpdf_structtree.h',
        'fpdf_dataavail.h',
        'fpdf_fwlevent.h',
        'fpdf_ext.h',
        'fpdf_transformpage.h',
        'fpdf_flatten.h',
        'fpdf_thumbnail.h',
      ].map(modulePath.resolve).toList(),
    ),
  ).generate();
}

/// Helper function to get PDFium instance.
///
/// This function downloads the PDFium module if necessary.
///
/// - [cacheRootPath]: The root directory to cache the downloaded PDFium module.
/// - [pdfiumRelease]: The release of PDFium to download. Defaults to [currentPDFiumRelease].
///
/// For macOS, the downloaded library is not codesigned. If you encounter issues loading the library,
/// you may need to manually codesign it using the following command:
///
/// ```
/// codesign --force --sign - <path_to_libpdfium.dylib>
/// ```
Future<Uri> getPdfium({
  required String cacheRootPath,
  String? pdfiumRelease = currentPDFiumRelease,
}) async {
  if (!await File(cacheRootPath).exists()) {
    await Directory(cacheRootPath).create(recursive: true);
  }
  final modulePath = await PDFiumDownloader.downloadAndGetPDFiumModulePath(
    cacheRootPath,
    pdfiumRelease: pdfiumRelease,
    os: OS.current,
    arch: Architecture.current,
  );
  return File.fromUri(modulePath).parent.parent.uri.resolve('include/');
}
