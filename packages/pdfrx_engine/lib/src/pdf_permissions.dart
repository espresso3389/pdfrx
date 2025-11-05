/// PDF permissions defined on PDF 32000-1:2008, Table 22.
class PdfPermissions {
  const PdfPermissions(this.permissions, this.securityHandlerRevision);

  /// User access permissions on on PDF 32000-1:2008, Table 22.
  final int permissions;

  /// Security handler revision.
  final int securityHandlerRevision;

  /// Determine whether the PDF file allows copying of the contents.
  bool get allowsCopying => (permissions & 4) != 0;

  /// Determine whether the PDF file allows document assembly.
  bool get allowsDocumentAssembly => (permissions & 8) != 0;

  /// Determine whether the PDF file allows printing of the pages.
  bool get allowsPrinting => (permissions & 16) != 0;

  /// Determine whether the PDF file allows modifying annotations, form fields, and their associated
  bool get allowsModifyAnnotations => (permissions & 32) != 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPermissions &&
        other.permissions == permissions &&
        other.securityHandlerRevision == securityHandlerRevision;
  }

  @override
  int get hashCode => permissions.hashCode ^ securityHandlerRevision.hashCode;
}
