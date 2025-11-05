import 'utils/list_equals.dart';

/// PDF [Explicit Destination](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374) the page and inner-page location to jump to.
class PdfDest {
  /// Create a [PdfDest].
  const PdfDest(this.pageNumber, this.command, this.params);

  /// Page number to jump to.
  final int pageNumber;

  /// Destination command.
  final PdfDestCommand command;

  /// Destination parameters. For more info, see [PdfDestCommand].
  final List<double?>? params;

  @override
  String toString() => 'PdfDest{pageNumber: $pageNumber, command: $command, params: $params}';

  /// Compact the destination.
  ///
  /// The method is used to compact the destination to reduce memory usage.
  /// [params] is typically growable and also modifiable. The method ensures that [params] is unmodifiable.
  PdfDest compact() {
    return params == null ? this : PdfDest(pageNumber, command, List.unmodifiable(params!));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfDest &&
        other.pageNumber == pageNumber &&
        other.command == command &&
        listEquals(other.params, params);
  }

  @override
  int get hashCode => pageNumber.hashCode ^ command.hashCode ^ params.hashCode;
}

/// [PDF 32000-1:2008, 12.3.2.2 Explicit Destinations, Table 151](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374)
enum PdfDestCommand {
  unknown('unknown'),
  xyz('xyz'),
  fit('fit'),
  fitH('fith'),
  fitV('fitv'),
  fitR('fitr'),
  fitB('fitb'),
  fitBH('fitbh'),
  fitBV('fitbv');

  /// Create a [PdfDestCommand] with the specified command name.
  const PdfDestCommand(this.name);

  /// Parse the command name to [PdfDestCommand].
  factory PdfDestCommand.parse(String name) {
    final nameLow = name.toLowerCase();
    return PdfDestCommand.values.firstWhere((e) => e.name == nameLow, orElse: () => PdfDestCommand.unknown);
  }

  /// Command name.
  final String name;
}
