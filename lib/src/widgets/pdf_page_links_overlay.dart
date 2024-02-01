import 'package:flutter/material.dart';

import '../../pdfrx.dart';

typedef PdfPageLinkWrapperWidgetBuilder = Widget Function(Widget child);

/// A widget that displays links on a page.
class PdfPageLinksOverlay extends StatefulWidget {
  const PdfPageLinksOverlay({
    required this.page,
    required this.pageRect,
    required this.params,
    this.wrapperBuilder,
    super.key,
  });

  final PdfPage page;
  final Rect pageRect;
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
    if (widget.page != oldWidget.page) {
      _initLinks();
    }
  }

  Future<void> _initLinks() async {
    links = await widget.page.loadLinks();
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
        final rectLink =
            rect.toRect(page: widget.page, scaledTo: widget.pageRect.size);
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
      left: widget.pageRect.left,
      top: widget.pageRect.top,
      width: widget.pageRect.width,
      height: widget.pageRect.height,
      child: Stack(children: linkWidgets),
    );
  }
}
