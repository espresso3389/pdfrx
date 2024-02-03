import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../pdfrx.dart';

/// Show error widget when pdf viewer failed to load pdf.
Widget pdfErrorWidget(
  BuildContext context,
  Object error, {
  StackTrace? stackTrace,
  bool bannerWarning = true,
}) {
  return Container(
    color: Colors.blue,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GestureRecognizerDisposer(builder: (context, markForDispose) {
            return SelectionArea(
              child: Text.rich(
                TextSpan(
                  children: [
                    const WidgetSpan(
                      child: Icon(
                        Icons.error,
                        size: 50,
                        color: Colors.yellow,
                      ),
                      alignment: PlaceholderAlignment.middle,
                    ),
                    TextSpan(
                      text: ' $error\n\n',
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    if (stackTrace != null)
                      TextSpan(
                        text: stackTrace.toString(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    if (error is PdfPasswordException &&
                        !kIsWeb &&
                        Platform.isWindows)
                      const TextSpan(
                        text:
                            '\n***On Windows, pdfium could not report errors correctly and every error is recognized as password error.',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.yellow,
                        ),
                      ),
                    if (bannerWarning)
                      TextSpan(
                        recognizer: markForDispose(
                          TapGestureRecognizer()
                            ..onTap = () {
                              launchUrlString(
                                  'https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/errorBannerBuilder.html');
                            },
                        ),
                        text:
                            '\n\nTo replace the error banner, set PdfViewerParams.errorBannerBuilder.',
                      ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

typedef _GestureRecognizerDisposerFunction = GestureRecognizer Function(
    GestureRecognizer recognizer);
typedef _GestureRecognizerDisposerBuilderFunction = Widget Function(
  BuildContext context,
  _GestureRecognizerDisposerFunction markForDispose,
);

class _GestureRecognizerDisposer extends StatefulWidget {
  const _GestureRecognizerDisposer({
    required this.builder,
    super.key,
  });

  final _GestureRecognizerDisposerBuilderFunction builder;

  @override
  State<_GestureRecognizerDisposer> createState() =>
      _GestureRecognizerDisposerState();
}

class _GestureRecognizerDisposerState
    extends State<_GestureRecognizerDisposer> {
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  GestureRecognizer _markForDispose(GestureRecognizer recognizer) {
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _markForDispose);
  }
}
