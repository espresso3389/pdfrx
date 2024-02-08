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
      PdfPageTextCache(textSearcher: widget.textSearcher);
  final scrollController = ScrollController();

  @override
  void initState() {
    widget.textSearcher.addListener(_searchResultUpdated);
    searchTextController.addListener(_searchTextUpdated);
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    widget.textSearcher.removeListener(_searchResultUpdated);
    searchTextController.removeListener(_searchTextUpdated);
    searchTextController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _searchTextUpdated() {
    widget.textSearcher.startTextSearch(searchTextController.text);
  }

  int? _currentSearchSession;
  final _matchIndexToListIndex = <int>[];
  final _listIndexToMatchIndex = <int>[];

  void _searchResultUpdated() {
    if (_currentSearchSession != widget.textSearcher.searchSession) {
      _currentSearchSession = widget.textSearcher.searchSession;
      _matchIndexToListIndex.clear();
      _listIndexToMatchIndex.clear();
    }
    for (int i = _matchIndexToListIndex.length;
        i < widget.textSearcher.matches.length;
        i++) {
      if (i == 0 ||
          widget.textSearcher.matches[i - 1].pageNumber !=
              widget.textSearcher.matches[i].pageNumber) {
        _listIndexToMatchIndex.add(-widget.textSearcher.matches[i]
            .pageNumber); // negative index to indicate page header
      }
      _matchIndexToListIndex.add(_listIndexToMatchIndex.length);
      _listIndexToMatchIndex.add(i);
    }

    if (mounted) setState(() {});
  }

  static const double itemHeight = 50;

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
                    textInputAction: TextInputAction.search,
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
                      _conditionScrollPosition();
                    }
                  : null,
              icon: const Icon(Icons.arrow_downward),
              iconSize: 20,
            ),
            IconButton(
              onPressed: (widget.textSearcher.currentIndex ?? 0) > 0
                  ? () async {
                      await widget.textSearcher.goToPrevMatch();
                      _conditionScrollPosition();
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
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            key: Key(searchTextController.text),
            controller: scrollController,
            itemCount: _listIndexToMatchIndex.length,
            itemBuilder: (context, index) {
              final matchIndex = _listIndexToMatchIndex[index];
              if (matchIndex >= 0) {
                final match = widget.textSearcher.matches[matchIndex];
                return SearchResultTile(
                  key: ValueKey(index),
                  match: match,
                  onTap: () async {
                    await widget.textSearcher.goToMatchOfIndex(matchIndex);
                    if (mounted) setState(() {});
                  },
                  pageTextStore: pageTextStore,
                  height: itemHeight,
                  isCurrent: matchIndex == widget.textSearcher.currentIndex,
                );
              } else {
                return Container(
                  height: itemHeight,
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Page ${-matchIndex}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  void _conditionScrollPosition() {
    final pos = scrollController.position;
    final newPos =
        itemHeight * _matchIndexToListIndex[widget.textSearcher.currentIndex!];
    if (newPos + itemHeight > pos.pixels + pos.viewportDimension) {
      scrollController.animateTo(
        newPos + itemHeight - pos.viewportDimension,
        duration: const Duration(milliseconds: 300),
        curve: Curves.decelerate,
      );
    } else if (newPos < pos.pixels) {
      scrollController.animateTo(
        newPos,
        duration: const Duration(milliseconds: 300),
        curve: Curves.decelerate,
      );
    }

    if (mounted) setState(() {});
  }
}

class SearchResultTile extends StatefulWidget {
  const SearchResultTile({
    super.key,
    required this.match,
    required this.onTap,
    required this.pageTextStore,
    required this.height,
    required this.isCurrent,
  });

  final PdfTextRangeWithFragments match;
  final void Function() onTap;
  final PdfPageTextCache pageTextStore;
  final double height;
  final bool isCurrent;

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

    return SizedBox(
      height: widget.height,
      child: Material(
        color: widget.isCurrent
            ? DefaultSelectionStyle.of(context).selectionColor!
            : null,
        child: InkWell(
          onTap: () => widget.onTap(),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.black12,
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: text,
          ),
        ),
      ),
    );
  }

  TextSpan createTextSpanForMatch(
      PdfPageText? pageText, PdfTextRangeWithFragments match,
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
class PdfPageTextCache {
  final PdfTextSearcher textSearcher;
  PdfPageTextCache({
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
