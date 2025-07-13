import 'dart:collection';

/// An unmodifiable sublist view of a list.
class UnmodifiableSublist<T> extends ListBase<T> {
  /// Creates an unmodifiable sublist view of the provided list.
  ///
  /// Please note that the class assumes the underlying list is also unmodifiable.
  /// If the underlying list is modified, the behavior of this class is undefined.
  UnmodifiableSublist(this._list, {int start = 0, int? end})
    : assert(start >= 0 && start <= _list.length && (end == null || end >= start)),
      _start = start,
      length = (end ?? _list.length) - start;
  final List<T> _list;
  final int _start;

  @override
  final int length;

  @override
  set length(int newLength) => throw UnsupportedError('Cannot modify the length of an unmodifiable list');

  @override
  T operator [](int index) => _list[index + _start];

  @override
  void operator []=(int index, T value) => throw UnsupportedError('Cannot modify an unmodifiable list');

  @override
  Iterator<T> get iterator => _list.getRange(_start, _start + length).iterator;
}
