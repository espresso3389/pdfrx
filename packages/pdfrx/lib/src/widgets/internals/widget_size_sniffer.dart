// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/material.dart';

/// A widget that sniffs the size of its child and calls the callback when the size changes.
class WidgetSizeSniffer extends StatefulWidget {
  const WidgetSizeSniffer({required this.child, this.onSizeChanged, super.key});

  final Widget child;
  final FutureOr<void> Function(GlobalRect rect)? onSizeChanged;

  @override
  State<WidgetSizeSniffer> createState() => _WidgetSizeSnifferState();
}

class _WidgetSizeSnifferState extends State<WidgetSizeSniffer> {
  Rect? _rect;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final r = context.findRenderObject();
      if (r is! RenderBox) return;
      final rect = Rect.fromPoints(r.localToGlobal(Offset.zero), r.localToGlobal(Offset(r.size.width, r.size.height)));
      if (_rect != rect) {
        _rect = rect;
        await widget.onSizeChanged?.call(GlobalRect(_rect!));
        if (mounted) {
          setState(() {});
        }
      }
    });
    return Offstage(offstage: _rect == null, child: widget.child);
  }
}

/// A class to hold the global rectangle and provide a method to convert it to local coordinates.
class GlobalRect {
  const GlobalRect(this.globalRect);

  final Rect globalRect;

  Rect? toLocal(BuildContext context) {
    final renderBox = context.findRenderObject();
    if (renderBox is RenderBox) {
      return Rect.fromPoints(
        renderBox.globalToLocal(globalRect.topLeft),
        renderBox.globalToLocal(globalRect.bottomRight),
      );
    }
    return null;
  }
}
