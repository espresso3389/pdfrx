/// Mixin that provides in-place shuffling capabilities for an array-like collection of items.
mixin ShuffleItemsInPlaceMixin {
  /// The current number of items.
  int get length;

  /// Moves [count] consecutive item(s) starting at [fromIndex] to [toIndex].
  void move(int fromIndex, int toIndex, int count);

  /// Removes [count] item(s) starting from the given [index].
  void remove(int index, int count);

  /// Duplicates the item(s) at the given [fromIndex] and inserts them at [toIndex].
  void duplicate(int fromIndex, int toIndex, int count);

  /// Inserts a new item at the given index. The [negativeItemIndex] indicates
  /// which new item, which is identified by the negative index.
  void insertNew(int index, int negativeItemIndex);

  /// Shuffles the items in place according to the given list of resulting item indices.
  ///
  /// For example, if the current items are [A, B, C, D] and the resultingItemIndices is [2, 0, 1],
  /// the resulting items will be [B, C, A].
  ///
  /// If the index is negative, a new item (of the negative index) is inserted at that position using [insertNew].
  ///
  /// If same index appears multiple times in resultingItemIndices, the item at the index should be duplicated
  /// accordingly; only one item can be moved, but the others are created using [duplicate].
  void shuffleInPlaceAccordingToIndices(List<int> resultingItemIndices) {
    final originalLength = length;
    if (resultingItemIndices.isEmpty) {
      if (originalLength > 0) {
        remove(0, originalLength);
      }
      return;
    }

    final tokens = <_ArrayOfItemsToken>[
      for (var i = 0; i < originalLength; i++) _ArrayOfItemsToken(originalIndex: i, isOriginal: true),
    ];

    final usageCounts = List<int>.filled(originalLength, 0);
    for (var i = 0; i < resultingItemIndices.length; i++) {
      final index = resultingItemIndices[i];
      if (index >= 0) {
        if (index >= originalLength) {
          throw RangeError('resultingItemIndices[$i] = $index is out of range for current length $originalLength');
        }
        usageCounts[index]++;
      }
    }

    for (var i = originalLength - 1; i >= 0; i--) {
      if (usageCounts[i] == 0) {
        remove(i, 1);
        tokens.removeAt(i);
      }
    }

    final placedCounts = List<int>.filled(originalLength, 0);
    var currentIndex = 0;

    while (currentIndex < resultingItemIndices.length) {
      if (currentIndex > tokens.length) {
        throw StateError('Destination index $currentIndex is out of range for current length ${tokens.length}.');
      }

      final target = resultingItemIndices[currentIndex];
      if (target >= 0) {
        final isFirst = placedCounts[target] == 0;
        if (isFirst) {
          final fromIndex = tokens.indexWhere((token) => token.originalIndex == target && token.isOriginal);
          if (fromIndex == -1) {
            throw StateError('Item at index $target could not be found for initial placement.');
          }

          var chunkLength = 1;
          while (currentIndex + chunkLength < resultingItemIndices.length && fromIndex + chunkLength < tokens.length) {
            final nextTarget = resultingItemIndices[currentIndex + chunkLength];
            if (nextTarget < 0 || placedCounts[nextTarget] > 0) break;
            final nextToken = tokens[fromIndex + chunkLength];
            if (!nextToken.isOriginal || nextToken.originalIndex != nextTarget) break;
            chunkLength++;
          }

          var placementIndex = currentIndex;
          if (fromIndex != currentIndex) {
            final removalIndices = List<int>.generate(chunkLength, (offset) => fromIndex + offset);
            move(fromIndex, currentIndex, chunkLength);
            final removedTokens = <_ArrayOfItemsToken>[];
            for (var i = removalIndices.length - 1; i >= 0; i--) {
              removedTokens.insert(0, tokens.removeAt(removalIndices[i]));
            }
            var insertIndex = currentIndex;
            for (final index in removalIndices) {
              if (index < currentIndex) {
                insertIndex--;
              }
            }
            if (insertIndex < 0) insertIndex = 0;
            if (insertIndex > tokens.length) insertIndex = tokens.length;
            tokens.insertAll(insertIndex, removedTokens);
            placementIndex = insertIndex;
          }

          for (var offset = 0; offset < chunkLength; offset++) {
            final token = tokens[placementIndex + offset];
            final originalIndex = token.originalIndex;
            if (originalIndex != null) {
              placedCounts[originalIndex]++;
            }
          }
          currentIndex += chunkLength;
          continue;
        } else {
          final sourceIndex = tokens.indexWhere((token) => token.originalIndex == target);
          if (sourceIndex == -1) {
            throw StateError('Item at index $target could not be found for duplication.');
          }
          duplicate(sourceIndex, currentIndex, 1);
          final newToken = _ArrayOfItemsToken(originalIndex: target, isOriginal: false);
          tokens.insert(currentIndex, newToken);
          placedCounts[target]++;
        }
      } else {
        insertNew(currentIndex, target);
        tokens.insert(currentIndex, const _ArrayOfItemsToken(originalIndex: null, isOriginal: false));
      }
      currentIndex++;
    }

    final expectedLength = resultingItemIndices.length;
    if (tokens.length > expectedLength) {
      final extra = tokens.length - expectedLength;
      remove(expectedLength, extra);
      tokens.removeRange(expectedLength, tokens.length);
    } else if (tokens.length < expectedLength) {
      throw StateError('Internal length mismatch after shuffling (expected $expectedLength, got ${tokens.length}).');
    }
  }
}

class _ArrayOfItemsToken {
  const _ArrayOfItemsToken({required this.originalIndex, required this.isOriginal});

  final int? originalIndex;
  final bool isOriginal;
}
