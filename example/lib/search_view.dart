// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:synchronized/extension.dart';

//
// Simple Text Search View
//
class TextSearchView extends StatefulWidget {
  const TextSearchView({
    super.key,
    required this.textSearcher,
  });

  final PdfTextSearcher textSearcher;

  @override
  State<TextSearchView> createState() => _TextSearchViewState();
}

class _TextSearchViewState extends State<TextSearchView> {
  final focusNode = FocusNode();
  final searchTextController = TextEditingController();
  late final pageTextStore =
      PdfPageTextStore(textSearcher: widget.textSearcher);

  @override
  void initState() {
    searchTextController.addListener(_searchTextUpdated);
    super.initState();
  }

  @override
  void dispose() {
    searchTextController.removeListener(_searchTextUpdated);
    searchTextController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _searchTextUpdated() {
    widget.textSearcher.startTextSearch(searchTextController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.textSearcher.isSearching
            ? LinearProgressIndicator(
                value: widget.textSearcher.searchProgress,
                minHeight: 4,
              )
            : const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TextField(
                    autofocus: true,
                    focusNode: focusNode,
                    controller: searchTextController,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.only(right: 50),
                    ),
                    textInputAction: TextInputAction.none,
                    // onSubmitted: (value) {
                    //   // just focus back to the text field
                    //   focusNode.requestFocus();
                    // },
                  ),
                  if (widget.textSearcher.hasMatches)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${widget.textSearcher.currentIndex! + 1} / ${widget.textSearcher.matches.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: (widget.textSearcher.currentIndex ?? 0) <
                      widget.textSearcher.matches.length
                  ? () async {
                      await widget.textSearcher.goToNextMatch();
                      if (mounted) setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.arrow_downward),
              iconSize: 20,
            ),
            IconButton(
              onPressed: (widget.textSearcher.currentIndex ?? 0) > 0
                  ? () async {
                      await widget.textSearcher.goToPrevMatch();
                      if (mounted) setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.arrow_upward),
              iconSize: 20,
            ),
            IconButton(
              onPressed: searchTextController.text.isNotEmpty
                  ? () {
                      searchTextController.text = '';
                      widget.textSearcher.resetTextSearch();
                      focusNode.requestFocus();
                    }
                  : null,
              icon: const Icon(Icons.close),
              iconSize: 20,
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            key: Key(searchTextController.text),
            itemCount: widget.textSearcher.matches.length,
            itemBuilder: (context, index) => SearchResultTile(
              key: ValueKey(index),
              match: widget.textSearcher.matches[index],
              onTap: () => widget.textSearcher
                  .goToMatch(widget.textSearcher.matches[index]),
              pageTextStore: pageTextStore,
              height: 50,
              isLast: index + 1 == widget.textSearcher.matches.length,
            ),
          ),
        ),
      ],
    );
  }
}

class SearchResultTile extends StatefulWidget {
  const SearchResultTile({
    super.key,
    required this.match,
    required this.onTap,
    required this.pageTextStore,
    required this.height,
    required this.isLast,
  });

  final PdfTextMatch match;
  final void Function() onTap;
  final PdfPageTextStore pageTextStore;
  final double height;
  final bool isLast;

  @override
  State<SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<SearchResultTile> {
  PdfPageText? pageText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _release() {
    if (pageText != null) {
      widget.pageTextStore.releaseText(pageText!.pageNumber);
    }
  }

  Future<void> _load() async {
    _release();
    pageText = await widget.pageTextStore.loadText(widget.match.pageNumber);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(createTextSpanForMatch(pageText, widget.match));

    return InkWell(
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.all(3),
              child: text,
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                color: Colors.black38,
                padding: const EdgeInsets.all(3),
                child: Text(
                  'Page ${widget.match.pageNumber}',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
            if (!widget.isLast)
              const Align(
                alignment: Alignment.bottomCenter,
                child: Divider(
                  height: 1,
                ),
              ),
          ],
        ),
      ),
      onTap: () => widget.onTap(),
    );
  }

  TextSpan createTextSpanForMatch(PdfPageText? pageText, PdfTextMatch match,
      {TextStyle? style}) {
    style ??= const TextStyle(
      fontSize: 14,
    );
    if (pageText == null) {
      return TextSpan(
        text: match.fragments.map((f) => f.text).join(),
        style: style,
      );
    }
    final fullText = pageText.fullText;
    int first = 0;
    for (int i = match.fragments.first.index - 1; i >= 0;) {
      if (fullText[i] == '\n') {
        first = i + 1;
        break;
      }
      i--;
    }
    int last = fullText.length;
    for (int i = match.fragments.last.end; i < fullText.length; i++) {
      if (fullText[i] == '\n') {
        last = i;
        break;
      }
    }

    final header =
        fullText.substring(first, match.fragments.first.index + match.start);
    final body = fullText.substring(match.fragments.first.index + match.start,
        match.fragments.last.index + match.end);
    final footer =
        fullText.substring(match.fragments.last.index + match.end, last);

    return TextSpan(
      children: [
        TextSpan(text: header),
        TextSpan(
          text: body,
          style: const TextStyle(
            backgroundColor: Colors.yellow,
          ),
        ),
        TextSpan(text: footer),
      ],
      style: style,
    );
  }
}

/// A helper class to cache loaded page texts.
class PdfPageTextStore {
  final PdfTextSearcher textSearcher;
  PdfPageTextStore({
    required this.textSearcher,
  });

  final _pageTextRefs = <int, _PdfPageTextRefCount>{};

  /// load the text of the given page number.
  Future<PdfPageText> loadText(int pageNumber) async {
    final ref = _pageTextRefs[pageNumber];
    if (ref != null) {
      ref.refCount++;
      return ref.pageText;
    }
    return await synchronized(() async {
      var ref = _pageTextRefs[pageNumber];
      if (ref == null) {
        final pageText = await textSearcher.loadText(pageNumber: pageNumber);
        ref = _pageTextRefs[pageNumber] = _PdfPageTextRefCount(pageText!);
      }
      ref.refCount++;
      return ref.pageText;
    });
  }

  /// Release the text of the given page number.
  void releaseText(int pageNumber) {
    final ref = _pageTextRefs[pageNumber]!;
    ref.refCount--;
    if (ref.refCount == 0) {
      _pageTextRefs.remove(pageNumber);
    }
  }
}

class _PdfPageTextRefCount {
  _PdfPageTextRefCount(this.pageText);
  final PdfPageText pageText;
  int refCount = 0;
}
