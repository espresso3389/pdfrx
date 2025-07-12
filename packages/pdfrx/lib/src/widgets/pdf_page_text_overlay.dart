import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../pdfrx.dart';
import '../utils/double_extensions.dart';

/// Function to be notified when the text selection is changed.
///
/// [selection] is the selected text ranges.
/// If page selection is cleared on page dispose (it means, the page is scrolled out of the view), [selection] is null.
/// Otherwise, [selection] is the selected text ranges. If no selection is made, [selection] is an empty list.
typedef PdfViewerPageTextSelectionChangeCallback = void Function(PdfTextRanges selection);

/// A widget that displays selectable text on a page.
///
/// If [PdfDocument.permissions] does not allow copying, the widget does not show anything.
class PdfPageTextOverlay extends StatefulWidget {
  const PdfPageTextOverlay({
    required this.selectables,
    required this.page,
    required this.pageRect,
    required this.selectionColor,
    required this.enabled,
    this.textCursor = SystemMouseCursors.text,
    this.onTextSelectionChange,
    super.key,
  });

  final SplayTreeMap<int, PdfPageTextSelectable> selectables;
  final bool enabled;
  final PdfPage page;
  final Rect pageRect;
  final PdfViewerPageTextSelectionChangeCallback? onTextSelectionChange;
  final Color selectionColor;
  final MouseCursor textCursor;

  @override
  State<PdfPageTextOverlay> createState() => _PdfPageTextOverlayState();

  /// Whether to show debug information.
  static bool isDebug = false;
}

class _PdfPageTextOverlayState extends State<PdfPageTextOverlay> {
  PdfPageText? _pageText;
  List<PdfPageTextFragment>? fragments;
  bool selectionShouldBeEnabled = false;

  @override
  void initState() {
    super.initState();
    _initText();
  }

  @override
  void didUpdateWidget(PdfPageTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      _initText();
    }
  }

  @override
  void dispose() {
    _release();

    super.dispose();
  }

  void _release() {
    if (_pageText != null) {
      _notifySelectionChange(PdfTextRanges.createEmpty(_pageText!));
    }
  }

  void _notifySelectionChange(PdfTextRanges ranges) {
    widget.onTextSelectionChange?.call(ranges);
  }

  Future<void> _initText() async {
    _release();
    final pageText = _pageText = await widget.page.loadText();
    final fragments = <PdfPageTextFragment>[];
    if (pageText.fragments.isNotEmpty) {
      double y = pageText.fragments[0].bounds.bottom;
      int start = 0;
      for (int i = 1; i < pageText.fragments.length; i++) {
        final fragment = pageText.fragments[i];
        if (!fragment.bounds.bottom.isAlmostIdentical(y, error: .25)) {
          fragments.addAll(pageText.fragments.sublist(start, i));
          y = fragment.bounds.bottom;
          start = i;
        }
      }
      if (start < pageText.fragments.length) {
        fragments.addAll(pageText.fragments.sublist(start, pageText.fragments.length));
      }
    }
    this.fragments = fragments;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (fragments == null || fragments!.isEmpty || widget.page.document.permissions?.allowsCopying == false) {
      return const SizedBox();
    }
    final registrar = SelectionContainer.maybeOf(context);
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      cursor: selectionShouldBeEnabled ? widget.textCursor : MouseCursor.defer,
      onHover: _onHover,
      child: IgnorePointer(
        ignoring: !(selectionShouldBeEnabled || _anySelections),
        child: _PdfTextWidget(registrar, this),
      ),
    );
  }

  bool get _anySelections {
    if (_pageText == null) return false;
    final pageSelection = widget.selectables[_pageText!.pageNumber];
    return pageSelection != null && pageSelection.value.hasSelection;
  }

  void _onHover(PointerHoverEvent event) {
    final point = event.localPosition.toPdfPoint(page: widget.page, scaledPageSize: widget.pageRect.size);

    final selectionShouldBeEnabled = isPointOnText(point);
    if (this.selectionShouldBeEnabled != selectionShouldBeEnabled) {
      this.selectionShouldBeEnabled = selectionShouldBeEnabled;
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool isPointOnText(PdfPoint point, {double margin = 5}) {
    for (final fragment in fragments!) {
      if (fragment.bounds.containsPoint(point, margin: margin)) {
        return true;
      }
    }
    return false;
  }
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextWidget extends LeafRenderObjectWidget {
  const _PdfTextWidget(this._registrar, this._state);

  final SelectionRegistrar? _registrar;

  final _PdfPageTextOverlayState _state;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final selectable = _PdfTextRenderBox(_state.widget.selectionColor, this);
    _state.widget.selectables[_state._pageText!.pageNumber] = selectable;
    return selectable;
  }

  @override
  void updateRenderObject(BuildContext context, _PdfTextRenderBox renderObject) {
    renderObject
      ..selectionColor = _state.widget.selectionColor
      ..registrar = _registrar;
    _state.widget.selectables[_state._pageText!.pageNumber] = renderObject;
  }
}

mixin PdfPageTextSelectable implements Selectable {
  PdfTextRanges get selectedRanges;
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextRenderBox extends RenderBox with PdfPageTextSelectable, Selectable, SelectionRegistrant {
  _PdfTextRenderBox(this._selectionColor, this._textWidget)
    : _geometry = ValueNotifier<SelectionGeometry>(_noSelection) {
    registrar = _textWidget._registrar;
    _geometry.addListener(markNeedsPaint);
  }

  final _PdfTextWidget _textWidget;

  static const SelectionGeometry _noSelection = SelectionGeometry(status: SelectionStatus.none, hasContent: true);

  final ValueNotifier<SelectionGeometry> _geometry;

  Color _selectionColor;
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  Rect get _pageRect => _textWidget._state.widget.pageRect;
  PdfPage get _page => _textWidget._state.widget.page;
  List<PdfPageTextFragment> get _fragments => _textWidget._state.fragments!;

  @override
  late final List<Rect> boundingBoxes = _fragments
      .map((f) => f.bounds.toRect(page: _page, scaledPageSize: size))
      .toList(growable: false);

  @override
  bool hitTestSelf(Offset position) {
    final point = position.toPdfPoint(page: _page, scaledPageSize: _pageRect.size);
    return _textWidget._state.isPointOnText(point);
  }

  @override
  void performLayout() {
    size = _textWidget._state.widget.pageRect.size;
  }

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _geometry.removeListener(listener);

  @override
  SelectionGeometry get value => _geometry.value;

  Rect _getSelectionHighlightRect() => Offset.zero & size;

  Offset? _start;
  Offset? _end;
  String? _selectedText;
  Rect? _selectedRect;
  Size? _sizeOnSelection;
  late PdfTextRanges _selectedRanges = PdfTextRanges.createEmpty(_textWidget._state._pageText!);

  @override
  PdfTextRanges get selectedRanges => _selectedRanges;

  void _notifySelectionChange() {
    _textWidget._state._notifySelectionChange(_selectedRanges);
  }

  void _updateGeometry() {
    _updateGeometryInternal();
    _notifySelectionChange();
  }

  void _updateGeometryInternal() {
    _selectedText = null;
    _selectedRect = null;
    _selectedRanges = PdfTextRanges.createEmpty(_textWidget._state._pageText!);

    if (_start == null || _end == null) {
      _geometry.value = _noSelection;
      return;
    }

    final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
    var selectionRect = Rect.fromPoints(_start!, _end!);
    if (renderObjectRect.intersect(selectionRect).isEmpty) {
      _geometry.value = _noSelection;
      return;
    }
    selectionRect = !selectionRect.isEmpty ? selectionRect : _getSelectionHighlightRect();

    final selectionRects = <Rect>[];
    final sb = StringBuffer();

    int searchLineEnd(int start) {
      final lastIndex = _fragments.length - 1;
      var last = _fragments[start];
      for (int i = start; i < lastIndex; i++) {
        final next = _fragments[i + 1];
        if (last.bounds.bottom != next.bounds.bottom) {
          return i + 1;
        }
        last = next;
      }
      return _fragments.length;
    }

    Iterable<({Rect rect, String text, PdfTextRange range})> enumerateCharRects(int start, int end) sync* {
      for (int i = start; i < end; i++) {
        final fragment = _fragments[i];
        for (int j = 0; j < fragment.charRects.length; j++) {
          yield (
            rect: fragment.charRects[j].toRect(page: _page, scaledPageSize: size),
            text: fragment.text.substring(j, j + 1),
            range: PdfTextRange(start: fragment.index + j, end: fragment.index + j + 1),
          );
        }
      }
    }

    ({Rect? rect, String text, List<PdfTextRange> ranges}) selectChars(int start, int end, Rect lineSelectRect) {
      Rect? rect;
      final ranges = <PdfTextRange>[];
      final sb = StringBuffer();
      for (final r in enumerateCharRects(start, end)) {
        if (!r.rect.intersect(lineSelectRect).isEmpty || r.rect.bottom < lineSelectRect.bottom) {
          sb.write(r.text);
          ranges.appendRange(r.range);
          if (rect == null) {
            rect = r.rect;
          } else {
            rect = rect.expandToInclude(r.rect);
          }
        }
      }
      return (rect: rect, text: sb.toString(), ranges: ranges);
    }

    int? lastLineEnd;
    Rect? lastLineStartRect;
    for (int i = 0; i < _fragments.length;) {
      final bounds = _fragments[i].bounds.toRect(page: _page, scaledPageSize: size);
      final intersects = !selectionRect.intersect(bounds).isEmpty;
      if (intersects) {
        final lineEnd = searchLineEnd(i);
        final chars = selectChars(
          lastLineEnd ?? i,
          lineEnd,
          lastLineStartRect != null ? lastLineStartRect.expandToInclude(selectionRect) : selectionRect,
        );
        lastLineStartRect = bounds;
        lastLineEnd = i = lineEnd;
        if (chars.rect == null) continue;
        sb.write(chars.text);
        selectionRects.add(chars.rect!);
        _selectedRanges.ranges.appendAllRanges(chars.ranges);
      } else {
        i++;
      }
    }
    if (selectionRects.isEmpty) {
      _geometry.value = _noSelection;
      return;
    }

    final selectedBounds = selectionRects.reduce((a, b) => a.expandToInclude(b));
    _selectedRect = Rect.fromLTRB(
      _start?.dx ?? selectedBounds.left,
      _start?.dy ?? selectedBounds.top,
      _end?.dx ?? selectedBounds.right,
      _end?.dy ?? selectedBounds.bottom,
    );
    _selectedText = sb.toString();

    final first = selectionRects.first;
    final firstSelectionPoint = SelectionPoint(
      localPosition: first.bottomLeft,
      lineHeight: first.height,
      handleType: TextSelectionHandleType.left,
    );
    final last = selectionRects.last;
    final secondSelectionPoint = SelectionPoint(
      localPosition: last.bottomRight,
      lineHeight: last.height,
      handleType: TextSelectionHandleType.right,
    );
    final bool isReversed;
    if (_start!.dy > _end!.dy) {
      isReversed = true;
    } else if (_start!.dy < _end!.dy) {
      isReversed = false;
    } else {
      isReversed = _start!.dx > _end!.dx;
    }

    _sizeOnSelection = size;
    _geometry.value = SelectionGeometry(
      status: _selectedText!.isNotEmpty ? SelectionStatus.uncollapsed : SelectionStatus.collapsed,
      hasContent: true,
      startSelectionPoint: isReversed ? secondSelectionPoint : firstSelectionPoint,
      endSelectionPoint: isReversed ? firstSelectionPoint : secondSelectionPoint,
      selectionRects: selectionRects,
    );
  }

  void _selectFragment(Offset point) {
    _selectedRanges = PdfTextRanges.createEmpty(_textWidget._state._pageText!);
    for (final fragment in _fragments) {
      final bounds = fragment.bounds.toRect(page: _page, scaledPageSize: size);
      if (bounds.contains(point)) {
        _start = bounds.topLeft;
        _end = bounds.bottomRight;
        _selectedRect = bounds;
        _selectedText = fragment.text;
        _sizeOnSelection = size;
        _geometry.value = SelectionGeometry(
          status: _selectedText!.isNotEmpty ? SelectionStatus.uncollapsed : SelectionStatus.collapsed,
          hasContent: true,
          startSelectionPoint: SelectionPoint(
            localPosition: _selectedRect!.bottomLeft,
            lineHeight: _selectedRect!.height,
            handleType: TextSelectionHandleType.left,
          ),
          endSelectionPoint: SelectionPoint(
            localPosition: _selectedRect!.bottomRight,
            lineHeight: _selectedRect!.height,
            handleType: TextSelectionHandleType.right,
          ),
          selectionRects: [bounds],
        );
        _selectedRanges.ranges.appendRange(PdfTextRange(start: fragment.index, end: fragment.end));
        return;
      }
    }
    _geometry.value = _noSelection;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (!_textWidget._state.widget.enabled) {
      return SelectionResult.none;
    }

    var result = SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final point = globalToLocal((event as SelectionEdgeUpdateEvent).globalPosition);
        final adjustedPoint = SelectionUtils.adjustDragOffset(renderObjectRect, point);
        if (event.type == SelectionEventType.startEdgeUpdate) {
          _start = adjustedPoint;
        } else {
          _end = adjustedPoint;
        }
        result = SelectionUtils.getResultBasedOnRect(renderObjectRect, point);
        break;
      case SelectionEventType.clear:
        _start = _end = null;
      case SelectionEventType.selectAll:
        _start = Offset.zero;
        _end = Offset.infinite;
      case SelectionEventType.selectWord:
        _selectFragment(globalToLocal((event as SelectWordSelectionEvent).globalPosition));
        _notifySelectionChange();
        return SelectionResult.none;
      case SelectionEventType.granularlyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as GranularlyExtendSelectionEvent;
        // Initialize the offset it there is no ongoing selection.
        if (_start == null || _end == null) {
          if (extendSelectionEvent.forward) {
            _start = _end = Offset.zero;
          } else {
            _start = _end = Offset.infinite;
          }
        }
        // Move the corresponding selection edge.
        final newOffset = extendSelectionEvent.forward ? Offset.infinite : Offset.zero;
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = extendSelectionEvent.forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = extendSelectionEvent.forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
      case SelectionEventType.directionallyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as DirectionallyExtendSelectionEvent;
        // Convert to local coordinates.
        final horizontalBaseLine = globalToLocal(Offset(event.dx, 0)).dx;
        final Offset newOffset;
        final bool forward;
        switch (extendSelectionEvent.direction) {
          case SelectionExtendDirection.backward:
          case SelectionExtendDirection.previousLine:
            forward = false;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.infinite;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction == SelectionExtendDirection.previousLine || horizontalBaseLine < 0) {
              newOffset = Offset.zero;
            } else {
              newOffset = Offset.infinite;
            }
          case SelectionExtendDirection.nextLine:
          case SelectionExtendDirection.forward:
            forward = true;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.zero;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction == SelectionExtendDirection.nextLine ||
                horizontalBaseLine > size.width) {
              newOffset = Offset.infinite;
            } else {
              newOffset = Offset.zero;
            }
        }
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
      // FIXME: #156/#157 handle new SelectionEventType.selectParagraph (currently only in master channel)
      default: // case SelectionEventType.selectParagraph:
        _start = _end = null;
    }
    _updateGeometry();
    return result;
  }

  @override
  SelectedContent? getSelectedContent() =>
      value.hasSelection && _selectedText != null ? SelectedContent(plainText: _selectedText!) : null;

  @override
  SelectedContentRange? getSelection() {
    if (_selectedRanges.ranges.isEmpty) return null;
    return SelectedContentRange(
      startOffset: _selectedRanges.ranges.first.start,
      endOffset: _selectedRanges.ranges.last.end,
    );
  }

  @override
  int get contentLength => _selectedRanges.pageText.fullText.length;

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) {
      return;
    }

    _startHandle = startHandle;
    _endHandle = endHandle;
    // FIXME: pushHandleLayers sometimes called after dispose...
    if (debugDisposed != true) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    final scale = _sizeOnSelection != null ? size.width / _sizeOnSelection!.width : 1.0;
    if (PdfPageTextOverlay.isDebug) {
      for (int i = 0; i < _fragments.length; i++) {
        final f = _fragments[i];
        final rect = f.bounds.toRect(page: _page, scaledPageSize: size);
        context.canvas.drawRect(
          rect.shift(offset),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.red
            ..strokeWidth = 1,
        );
      }

      if (_selectedRect != null) {
        context.canvas.drawRect(
          (_selectedRect! * scale).shift(offset),
          Paint()
            ..style = PaintingStyle.fill
            ..color = Colors.blue.withAlpha(100),
        );
      }
    }

    if (!_geometry.value.hasSelection) {
      return;
    }

    for (final rect in _geometry.value.selectionRects) {
      context.canvas.drawRect(
        (rect * scale).shift(offset),
        Paint()
          ..style = PaintingStyle.fill
          ..color = _selectionColor,
      );
    }

    if (_startHandle != null) {
      context.pushLayer(
        LeaderLayer(link: _startHandle!, offset: offset + (value.startSelectionPoint!.localPosition * scale))
          ..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }
    if (_endHandle != null) {
      context.pushLayer(
        LeaderLayer(link: _endHandle!, offset: offset + (value.endSelectionPoint!.localPosition * scale))
          ..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }

    // if (size != _sizeOnSelection) {
    //   Future.microtask(
    //     () {
    //       final sp = _geometry.value.startSelectionPoint;
    //       final ep = _geometry.value.endSelectionPoint;
    //       if (sp == null || ep == null) return;
    //       _sizeOnSelection = size;
    //       _selectedRect = _selectedRect! * scale;
    //       _geometry.value = _geometry.value.copyWith(
    //         startSelectionPoint: SelectionPoint(
    //             handleType: sp.handleType,
    //             lineHeight: sp.lineHeight * scale,
    //             localPosition: sp.localPosition * scale),
    //         endSelectionPoint: SelectionPoint(
    //             handleType: ep.handleType,
    //             lineHeight: ep.lineHeight * scale,
    //             localPosition: ep.localPosition * scale),
    //         selectionRects:
    //             _geometry.value.selectionRects.map((r) => r * scale).toList(),
    //       );
    //       markNeedsPaint();
    //     },
    //   );
    //   return;
    // }
  }
}
