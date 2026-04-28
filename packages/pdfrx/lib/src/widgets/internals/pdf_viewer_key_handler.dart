// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../pdfrx.dart';

/// A widget that handles key events for the PDF viewer.
class PdfViewerKeyHandler extends StatefulWidget {
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
  State<PdfViewerKeyHandler> createState() => _PdfViewerKeyHandlerState();
}

class _PdfViewerKeyHandlerState extends State<PdfViewerKeyHandler> {
  // Tracks keys whose KeyDown we reported as handled, so we can also claim
  // their matching KeyUp. Unhandled keys (e.g. Android system back) must fall
  // through to let the platform process them. See #585.
  final _handledKeys = <LogicalKeyboardKey>{};

  @override
  Widget build(BuildContext context) {
    final childBuilder = Builder(
      builder: (context) {
        final focusNode = Focus.maybeOf(context);
        if (focusNode == null) {
          return widget.child;
        }
        return ListenableBuilder(listenable: focusNode, builder: (context, _) => widget.child);
      },
    );
    if (!widget.params.enabled) {
      return childBuilder;
    }

    return Focus(
      focusNode: widget.params.focusNode,
      parentNode: widget.params.parentNode,
      autofocus: widget.params.autofocus,
      canRequestFocus: widget.params.canRequestFocus,
      onFocusChange: widget.onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (widget.onKeyRepeat(widget.params, event.logicalKey, event is KeyDownEvent)) {
            _handledKeys.add(event.logicalKey);
            return KeyEventResult.handled;
          }
        } else if (event is KeyUpEvent) {
          if (_handledKeys.remove(event.logicalKey)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: childBuilder,
    );
  }
}
