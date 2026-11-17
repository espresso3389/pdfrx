import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';

/// A declarative, value-type strategy that computes page geometry for the viewer.
///
/// A [PdfLayout] is the *configuration* for how pages are positioned, not the geometry
/// itself. It produces a [PdfPageLayout] (page rects + document size) on demand via [resolve].
///
/// It is the value-type successor to the [PdfViewerParams.layoutPages] closure. Both yield a
/// [PdfPageLayout]; the viewer tries them in this order:
///
/// ```text
/// params.layout?.resolve(...)  →  params.layoutPages(...)  →  built-in default
/// ```
///
/// Adding a [PdfLayout] is non-breaking: [PdfViewerParams.layoutPages] is untouched and still
/// runs when [PdfViewerParams.layout] is null.
///
/// Unlike a closure, a [PdfLayout] can take part in [PdfViewerParams] equality, so a layout
/// change is detected and relayouts automatically (a closure changes identity on almost every
/// build and is ignored until a manual [PdfViewerController.invalidate]). Implementations must:
///
/// * be value types with correct [operator ==]/[hashCode] over their config fields, and a
///   `const` constructor where possible;
/// * use comparable scalar/enum fields only — no stored closures, and no stored viewport. The
///   viewport is a call-time argument to [resolve], never a field, so two layouts with the same
///   config resolved at different viewport sizes stay equal (a resize relayouts without changing
///   equality).
abstract class PdfLayout {
  const PdfLayout();

  /// Computes the page geometry for [pages] given the current [viewport] and [params].
  ///
  /// Returns a [PdfPageLayout] — the list of per-page rects in document coordinates
  /// plus the overall document size.
  ///
  /// [viewport] is a runtime input only. Implementations must not retain it; doing so
  /// would break the equality invariant described on the class.
  PdfPageLayout resolve({required List<PdfPage> pages, required Size viewport, required PdfViewerParams params});

  /// Subclasses must implement value equality over their configuration fields.
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}
