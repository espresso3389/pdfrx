/// How each page is sized to fit the viewport.
///
/// [fill] and [fit] scale each page's rect to fit. [none] keeps native sizes. [cover] also keeps
/// native geometry, but the size delegate zooms the whole document to fill the viewport.
/// Per-page fit lives in the rects because it varies per page; cover is one document-wide zoom,
/// so it can't.
enum PdfFitMode {
  /// Scale each page to fit entirely within the viewport. Margins may appear when page and
  /// viewport aspect ratios differ.
  fit,

  /// Scale each page to fill the cross axis (width for vertical scroll). Along the main axis
  /// a page may extend past the viewport (may crop).
  fill,

  /// Keep native page size; the size delegate zooms so the whole document fills the viewport
  /// (may crop). Uses the delegate's `coverScale`.
  cover,

  /// No scaling; native page size.
  none,
}
