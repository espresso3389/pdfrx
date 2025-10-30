import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

Future<void> savePdf(Uint8List bytes, {String? suggestedName}) async {
  if (Platform.isIOS || Platform.isAndroid) {
    final xFile = XFile.fromData(
      bytes,
      name: suggestedName ?? 'document.pdf',
      mimeType: 'application/pdf',
    );
    await Share.shareXFiles([xFile]);
    return;
  }
  final savePath = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      const XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );

  if (savePath != null) {
    final file = File(savePath.path);
    await file.writeAsBytes(bytes);
  }
}
