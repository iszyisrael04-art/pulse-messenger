import 'dart:convert';
import '../lib/appearance_model.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final picked = PulseAppearanceSettings(
    mode: 'system',
    wallpaper: 19,
    customFile: 'local-photo.png',
    matchWallpaper: false,
    seed: 0xffaa3355,
    customSeed: 0xff112233,
    dim: .65,
    splash: 'wave',
    loading: 'dots',
  );
  final restored = PulseAppearanceSettings.fromJson(
    Map<String, dynamic>.from(jsonDecode(jsonEncode(picked.toJson())) as Map),
  );
  expect(
    restored.mode == 'system' &&
        restored.wallpaper == 19 &&
        restored.customFile == 'local-photo.png' &&
        restored.loading == 'dots' &&
        restored.seed == 0xffaa3355,
    'Saved appearance did not round-trip',
  );
  final corrupt = PulseAppearanceSettings.fromJson({
    'mode': 'missing',
    'wallpaper': 999,
    'customFile': '../../private.png',
    'seed': -1,
    'customSeed': 'red',
    'dim': double.infinity,
    'splash': 12,
    'loading': 'unknown',
  });
  expect(
    corrupt.wallpaper == 0 &&
        corrupt.customFile == null &&
        corrupt.mode == 'dark' &&
        corrupt.dim == .25 &&
        corrupt.loading == 'pulse',
    'Unsafe preference fallback',
  );
  expect(
    PulseAppearanceSettings.fromJson({
          'customFile': 'C:\\secret.png',
        }).customFile ==
        null,
    'Absolute path accepted',
  );
  expect(
    PulseAppearanceSettings.fromJson({'dim': 9}).dim == .8,
    'Dimming limit failed',
  );
  expect(
    restored.copy(clearCustom: true).customFile == null &&
        restored.copy(mode: 'light').wallpaper == 19,
    'Wallpaper reset lost unrelated choices',
  );
  expect(
    pulseWallpaperNames.length == 20 &&
        pulseWallpaperNames.toSet().length == 20,
    'Wallpaper library incomplete',
  );
  print(
    'PASS: preference round-trip, corrupt-value recovery, unsafe-path rejection, dimming bounds and default reset',
  );
}
