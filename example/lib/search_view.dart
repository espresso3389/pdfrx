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
                    controller: searchTextController,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.only(right: 50),
                    ),
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
              onPressed: () => widget.textSearcher.goToNextMatch(),
              icon: const Icon(Icons.arrow_downward),
              iconSize: 20,
            ),
            IconButton(
              onPressed: () => widget.textSearcher.goToPrevMatch(),
              icon: const Icon(Icons.arrow_upward),
              iconSize: 20,
            ),
            IconButton(
              onPressed: () {
                searchTextController.text = '';
                widget.textSearcher.resetTextSearch();
              },
              icon: const Icon(Icons.close),
              iconSize: 20,
            ),
          ],
        ),
        if (widget.textSearcher.hasMatches)
          Expanded(
            child: ListView.separated(
              itemCount: widget.textSearcher.matches.length,
              itemBuilder: (context, index) => SearchResultTile(
                match: widget.textSearcher.matches[index],
                onTap: () => widget.textSearcher
                    .goToMatch(widget.textSearcher.matches[index]),
                pageTextStore: pageTextStore,
              ),
              separatorBuilder: (context, index) => const Divider(),
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
  });

  final PdfTextMatch match;
  final void Function() onTap;
  final PdfPageTextStore pageTextStore;

  @override
  State<SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<SearchResultTile> {
  PdfPageText? pageText;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      pageText = await widget.pageTextStore.loadText(widget.match.pageNumber);
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (pageText != null) {
      widget.pageTextStore.releaseText(widget.match.pageNumber);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget text;
    if (pageText == null) {
      text = Text('Page ${widget.match.pageNumber}');
    } else {
      text = Text.rich(test(pageText!, widget.match));
    }

    return ListTile(
      title: text,
      subtitle: Align(
        alignment: Alignment.bottomRight,
        child: Text(
          'Page ${widget.match.pageNumber}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      onTap: () => widget.onTap(),
    );
  }

  TextSpan test(PdfPageText pageText, PdfTextMatch match) {
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
      style: const TextStyle(
        fontSize: 14,
      ),
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
  void releaseText(int pageNumber) => synchronized(
        () {
          final ref = _pageTextRefs[pageNumber]!;
          ref.refCount--;
          if (ref.refCount == 0) {
            _pageTextRefs.remove(pageNumber);
          }
        },
      );
}

class _PdfPageTextRefCount {
  _PdfPageTextRefCount(this.pageText);
  final PdfPageText pageText;
  int refCount = 0;
}
