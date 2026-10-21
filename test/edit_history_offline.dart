import '../lib/edit_history.dart';

void check(bool value) {
  if (!value) throw StateError('Edit history regression');
}

void main() {
  final history = PulseEditHistory<int>(limit: 2);
  check(history.undo(0) == 0 && history.redo(0) == 0);
  history.remember(0);
  history.remember(1);
  history.remember(2);
  check(history.undo(3) == 2);
  check(history.undo(2) == 1);
  check(!history.canUndo);
  check(history.redo(1) == 2);
  history.remember(2);
  check(!history.canRedo);
  check(history.undo(4) == 2);
  check(history.redo(2) == 4);
  final edits = PulseEditHistory<({double start, String text})>();
  edits.remember((start: 0, text: ''));
  final previous = edits.undo((start: 12, text: 'Pulse'));
  check(previous == (start: 0.0, text: ''));
  check(edits.redo(previous) == (start: 12.0, text: 'Pulse'));
  print('Edit history checks passed.');
}
