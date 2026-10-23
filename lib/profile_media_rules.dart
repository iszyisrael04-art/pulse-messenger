const maxProfileVideoMs = 5000;
bool isProfileVideo(String? path) =>
    path?.toLowerCase().endsWith('.mp4') == true;
String profilePosterPath(String path) =>
    '${path.substring(0, path.length - 4)}-poster.jpg';
({int start, int end}) profileVideoRange(int durationMs, int selectedStart) {
  if (durationMs <= 0) throw ArgumentError('Video duration must be positive');
  final length = durationMs.clamp(1, maxProfileVideoMs);
  final start = selectedStart.clamp(0, durationMs - length);
  return (start: start, end: start + length);
}
