const pulsePrivacyVersion = '2026-10-17';

bool needsPrivacyAgreement({
  required bool register,
  required bool reset,
  required bool codeSent,
}) => register && !reset && !codeSent;

class PulseExitPresses {
  DateTime? _last;
  bool press(DateTime now) {
    final last = _last;
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) <= const Duration(seconds: 2)) {
      _last = null;
      return true;
    }
    _last = now;
    return false;
  }

  void reset() => _last = null;
}

bool profileMotionAllowed(
  DateTime? expiry,
  DateTime now, {
  bool reducedMotion = false,
  bool visible = true,
}) => !reducedMotion && visible && expiry != null && expiry.isAfter(now);

const pulseProfileBackgrounds = {
  'classic': 'Classic',
  'aurora': 'Aurora',
  'sunset': 'Sunset',
  'midnight': 'Midnight',
  'ocean': 'Ocean',
  'bloom': 'Bloom',
  'paper': 'Studio',
  'circuit': 'Circuit',
};
const pulseSignalModes = {
  'creating': 'Creating',
  'collaborating': 'Open to collaborate',
  'learning': 'Learning',
  'available': 'Available to help',
};

String compactProfileCount(Object? value) {
  final count = int.tryParse(value?.toString() ?? '') ?? 0;
  if (count < 1000) return '${count < 0 ? 0 : count}';
  final unit = count >= 1000000 ? 1000000 : 1000;
  final number = ((count / unit * 10).floor() / 10)
      .toStringAsFixed(1)
      .replaceFirst(RegExp(r'\.0$'), '');
  return '$number${unit == 1000000 ? 'M' : 'K'}';
}
