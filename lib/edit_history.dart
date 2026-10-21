/// Bounded edit history. Preview playback and generated covers are not edits.
class PulseEditHistory<T> {
  PulseEditHistory({this.limit = 40}) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
  }
  final int limit;
  final _past = <T>[];
  final _future = <T>[];
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  void remember(T value) {
    if (_past.isEmpty || _past.last != value) _past.add(value);
    if (_past.length > limit) _past.removeAt(0);
    _future.clear();
  }

  T undo(T current) {
    if (!canUndo) return current;
    _future.add(current);
    return _past.removeLast();
  }

  T redo(T current) {
    if (!canRedo) return current;
    _past.add(current);
    return _future.removeLast();
  }
}
