import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:jpeg_encode/jpeg_encode.dart';
import 'package:share_plus/share_plus.dart';

Future<void> savePdf(Uint8List bytes, {String? suggestedName}) async {
  if (Platform.isIOS || Platform.isAndroid) {
    final xFile = XFile.fromData(bytes, name: suggestedName ?? 'document.pdf', mimeType: 'application/pdf');
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

typedef CalculateTargetSize = ({int width, int height}) Function(int originalWidth, int originalHeight);

class JpegData {
  const JpegData(this.data, this.width, this.height);
  final Uint8List data;
  final int width;
  final int height;
}

Future<JpegData> compressImageToJpeg(
  Uint8List imageData, {
  CalculateTargetSize? calculateTargetSize,
  int quality = 90,
}) async {
  calculateTargetSize ??= (w, h) => (width: w, height: h);
  final buffer = await ui.ImmutableBuffer.fromUint8List(imageData);
  final codec = await PaintingBinding.instance.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (w, h) {
      final size = calculateTargetSize!(w, h);
      return ui.TargetImageSize(width: size.width, height: size.height);
    },
  );
  final frameInfo = await codec.getNextFrame();
  final rgba = (await frameInfo.image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final byteData = await _jpegEncodeAsync(rgba, frameInfo.image.width, frameInfo.image.height, quality);
  codec.dispose();
  return JpegData(byteData.buffer.asUint8List(), frameInfo.image.width, frameInfo.image.height);
}

Future<Uint8List> _jpegEncodeAsync(Uint8List rgba, int width, int height, int quality) async {
  return await compute((jpegParams) {
    final (rgba, width, height, quality) = jpegParams;
    return JpegEncoder().compress(rgba, width, height, quality);
  }, (rgba, width, height, quality));
}

final isWindowsDesktop = Platform.isWindows;
