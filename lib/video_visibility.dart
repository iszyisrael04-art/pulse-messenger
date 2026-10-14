import 'dart:math' as math;

bool pulseVideoVisible(
  double top,
  double height,
  double viewport, {
  double topInset = 80,
  double bottomInset = 80,
}) {
  if (!top.isFinite ||
      !height.isFinite ||
      !viewport.isFinite ||
      height <= 0 ||
      viewport <= topInset + bottomInset)
    return false;
  final overlap = math.max(
    0.0,
    math.min(top + height, viewport - bottomInset) - math.max(top, topInset),
  );
  return overlap / height > .55;
}
