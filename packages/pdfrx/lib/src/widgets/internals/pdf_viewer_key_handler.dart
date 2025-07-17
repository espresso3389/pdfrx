// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../pdfrx.dart';

/// A widget that handles key events for the PDF viewer.
class PdfViewerKeyHandler extends StatefulWidget {
  const PdfViewerKeyHandler({required this.child, required this.onKeyRepeat, required this.params, super.key});

  /// Called on every key repeat.
  ///
  /// See [PdfViewerOnKeyCallback] for the parameters.
  final bool Function(PdfViewerKeyHandlerParams, LogicalKeyboardKey, bool) onKeyRepeat;
  final PdfViewerKeyHandlerParams params;
  final Widget child;

  @override
  State<PdfViewerKeyHandler> createState() => _PdfViewerKeyHandlerState();
}

class _PdfViewerKeyHandlerState extends State<PdfViewerKeyHandler> {
  Timer? _timer;
  LogicalKeyboardKey? _currentKey;

  void _startRepeating(FocusNode node, LogicalKeyboardKey key) {
    _currentKey = key;

    // Initial delay before starting to repeat
    _timer = Timer(widget.params.initialDelay, () {
      // Start repeating at the specified interval
      _timer = Timer.periodic(widget.params.repeatInterval, (_) {
        widget.onKeyRepeat(widget.params, _currentKey!, false);
      });
    });
  }

  void _stopRepeating() {
    _timer?.cancel();
    _timer = null;
    _currentKey = null;
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.params.focusNode,
      parentNode: widget.params.parentNode,
      autofocus: widget.params.autofocus,
      canRequestFocus: widget.params.canRequestFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Key pressed down
          if (_currentKey == null) {
            if (widget.onKeyRepeat(widget.params, event.logicalKey, true)) {
              _startRepeating(node, event.logicalKey);
              return KeyEventResult.handled;
            }
          }
        } else if (event is KeyUpEvent) {
          // Key released
          if (_currentKey == event.logicalKey) {
            _stopRepeating();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focusNode = Focus.of(context);
          return ListenableBuilder(
            listenable: focusNode,
            builder: (context, _) {
              return widget.child;
            },
          );
        },
      ),
    );
  }
}
