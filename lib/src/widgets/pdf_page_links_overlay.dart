import 'package:flutter/material.dart';

import '../../pdfrx.dart';

typedef PdfPageLinkWrapperWidgetBuilder = Widget Function(Widget child);

/// A widget that displays links on a page.
class PdfPageLinksOverlay extends StatefulWidget {
  const PdfPageLinksOverlay({
    required this.converter,
    required this.params,
    this.wrapperBuilder,
    super.key,
  });

  final PdfPageCoordsConverter converter;
  final PdfViewerParams params;

  /// Currently, the handler is used to wrap the actual link widget with [Listener] not to absorb wheel-events.
  final PdfPageLinkWrapperWidgetBuilder? wrapperBuilder;

  @override
  State<PdfPageLinksOverlay> createState() => _PdfPageLinksOverlayState();
}

class _PdfPageLinksOverlayState extends State<PdfPageLinksOverlay> {
  List<PdfLink>? links;

  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  @override
  void didUpdateWidget(covariant PdfPageLinksOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.converter.page != oldWidget.converter.page) {
      _initLinks();
    }
  }

  Future<void> _initLinks() async {
    links = await widget.converter.page.loadLinks();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (links == null) return const SizedBox();

    final linkWidgets = <Widget>[];
    for (final link in links!) {
      for (final rect in link.rects) {
        final rectLink = widget.converter.toRect(rect);
        final linkWidget =
            widget.params.linkWidgetBuilder!(context, link, rectLink.size);
        if (linkWidget != null) {
          linkWidgets.add(
            Positioned(
              left: rectLink.left,
              top: rectLink.top,
              width: rectLink.width,
              height: rectLink.height,
              child: widget.wrapperBuilder?.call(linkWidget) ?? linkWidget,
            ),
          );
        }
      }
    }

    return Positioned(
      left: widget.converter.pageRect.left,
      top: widget.converter.pageRect.top,
      width: widget.converter.pageRect.width,
      height: widget.converter.pageRect.height,
      child: Stack(children: linkWidgets),
    );
  }
}
