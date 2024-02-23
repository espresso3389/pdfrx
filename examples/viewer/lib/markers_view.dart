import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class Marker {
  final Color color;
  final PdfTextRanges ranges;

  Marker(this.color, this.ranges);
}

class MarkersView extends StatefulWidget {
  const MarkersView({
    super.key,
    required this.markers,
    this.onTap,
    this.onDeleteTap,
  });

  final List<Marker> markers;
  final void Function(Marker ranges)? onTap;
  final void Function(Marker ranges)? onDeleteTap;

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
                    child: Text(
                        'Page #${marker.ranges.pageNumber} - ${marker.ranges.text}'),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => widget.onDeleteTap?.call(marker),
                ),
              ),
            ],
          ),
        );
      },
      itemCount: widget.markers.length,
    );
  }
}
