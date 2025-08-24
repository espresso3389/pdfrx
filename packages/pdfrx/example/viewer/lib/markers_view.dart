import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class Marker {
  Marker(this.color, this.range);
  final Color color;
  final PdfPageTextRange range;
}

class MarkersView extends StatefulWidget {
  const MarkersView({required this.markers, super.key, this.onTap, this.onDeleteTap});

  final List<Marker> markers;
  final void Function(Marker marker)? onTap;
  final void Function(Marker marker)? onDeleteTap;

  @override
  State<MarkersView> createState() => _MarkersViewState();
}

class _MarkersViewState extends State<MarkersView> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, index) {
        final marker = widget.markers[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Stack(
            children: [
              Material(
                color: marker.color.withAlpha(100),
                child: InkWell(
                  onTap: () => widget.onTap?.call(marker),
                  child: SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: Text('Page #${marker.range.pageNumber} - ${marker.range.text}'),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(icon: const Icon(Icons.delete), onPressed: () => widget.onDeleteTap?.call(marker)),
              ),
            ],
          ),
        );
      },
      itemCount: widget.markers.length,
    );
  }
}
