import 'package:flutter/foundation.dart';

/// PDF annotation information extracted from PDF links.
///
/// Contains metadata about PDF annotations such as author, content, and dates.
@immutable
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
    final buffer = StringBuffer('PdfAnnotation{');
    final fields = <String>[];

    if (author != null) fields.add('author: $author');
    if (content != null) fields.add('content: $content');
    if (subject != null) fields.add('subject: $subject');
    if (modificationDate != null) fields.add('modDate: $modificationDate');
    if (creationDate != null) fields.add('createDate: $creationDate');

    buffer.write(fields.join(', '));
    buffer.write('}');
    return buffer.toString();
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
  int get hashCode =>
      author.hashCode ^ content.hashCode ^ subject.hashCode ^ modificationDate.hashCode ^ creationDate.hashCode;

  /// Creates a copy with the given fields replaced with new values.
  PdfAnnotation copyWith({
    String? author,
    String? content,
    String? subject,
    String? modificationDate,
    String? creationDate,
  }) {
    return PdfAnnotation(
      author: author ?? this.author,
      content: content ?? this.content,
      subject: subject ?? this.subject,
      modificationDate: modificationDate ?? this.modificationDate,
      creationDate: creationDate ?? this.creationDate,
    );
  }

  /// Converts to a map for serialization.
  Map<String, dynamic> toJson() {
    return {
      if (author != null) 'author': author,
      if (content != null) 'content': content,
      if (subject != null) 'subject': subject,
      if (modificationDate != null) 'modificationDate': modificationDate,
      if (creationDate != null) 'creationDate': creationDate,
    };
  }

  /// Creates from a map for deserialization.
  factory PdfAnnotation.fromJson(Map<String, dynamic> json) {
    return PdfAnnotation(
      author: json['author'] as String?,
      content: json['content'] as String?,
      subject: json['subject'] as String?,
      modificationDate: json['modificationDate'] as String?,
      creationDate: json['creationDate'] as String?,
    );
  }
}
