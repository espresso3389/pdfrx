/// PDF annotation information extracted from PDF links.
///
/// Contains metadata about PDF annotations such as author, content, and dates.
class PdfAnnotation {
  const PdfAnnotation({this.author, this.content, this.subject, this.modificationDate, this.creationDate});

  /// The author/creator of the annotation (PDF field: T - Title).
  final String? author;

  /// The content/text of the annotation (PDF field: Contents).
  final String? content;

  /// The subject of the annotation (PDF field: Subj).
  final String? subject;

  /// The modification date of the annotation (PDF field: M).
  final String? modificationDate;

  /// The creation date of the annotation (PDF field: CreationDate).
  final String? creationDate;

  /// Returns true if all fields are null.
  bool get isEmpty =>
      author == null && content == null && subject == null && modificationDate == null && creationDate == null;

  /// Returns true if at least one field is not null.
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() {
    return 'PdfAnnotation{author: $author, content: $content, subject: $subject, '
        'modificationDate: $modificationDate, creationDate: $creationDate}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfAnnotation &&
        other.author == author &&
        other.content == content &&
        other.subject == subject &&
        other.modificationDate == modificationDate &&
        other.creationDate == creationDate;
  }

  @override
  int get hashCode {
    return author.hashCode ^ content.hashCode ^ subject.hashCode ^ modificationDate.hashCode ^ creationDate.hashCode;
  }
}
