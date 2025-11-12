// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../pdfrx.dart';

/// A widget that handles key events for the PDF viewer.
class PdfViewerKeyHandler extends StatelessWidget {
  const PdfViewerKeyHandler({
    required this.child,
    required this.onKeyRepeat,
    required this.params,
    this.onFocusChange,
    super.key,
  });

  /// Called on every key repeat.
  ///
  /// See [PdfViewerOnKeyCallback] for the parameters.
  final bool Function(PdfViewerKeyHandlerParams, LogicalKeyboardKey, bool) onKeyRepeat;
  final ValueChanged<bool>? onFocusChange;
  final PdfViewerKeyHandlerParams params;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final childBuilder = Builder(
      builder: (context) => ListenableBuilder(listenable: Focus.of(context), builder: (context, _) => child),
    );
    if (!params.enabled) {
      return childBuilder;
    }

    return Focus(
      focusNode: params.focusNode,
      parentNode: params.parentNode,
      autofocus: params.autofocus,
      canRequestFocus: params.canRequestFocus,
      onFocusChange: onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (onKeyRepeat(params, event.logicalKey, event is KeyDownEvent)) {
            return KeyEventResult.handled;
          }
        } else if (event is KeyUpEvent) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: childBuilder,
    );
  }
}
