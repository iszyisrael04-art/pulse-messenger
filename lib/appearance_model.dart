const pulseWallpaperNames = <String>[
  'Pulse Mint',
  'Violet Night',
  'Ocean Blue',
  'Sunset Coral',
  'Golden Hour',
  'Rose Garden',
  'Forest Mist',
  'Arctic Sky',
  'Midnight Ink',
  'Lavender Dream',
  'Peach Cloud',
  'Electric Lime',
  'Deep Space',
  'Cherry Glow',
  'Desert Sand',
  'Aurora',
  'Slate Calm',
  'Royal Blue',
  'Aqua Wave',
  'Monochrome',
];

class PulseAppearanceSettings {
  PulseAppearanceSettings({
    this.mode = 'dark',
    this.wallpaper = 0,
    this.customFile,
    this.matchWallpaper = true,
    this.seed = 0xff00bfa6,
    this.customSeed = 0xff00bfa6,
    this.dim = .25,
    this.splash = 'minimal',
    this.loading = 'pulse',
  });
  final String mode, splash, loading;
  final int wallpaper, seed, customSeed;
  final String? customFile;
  final bool matchWallpaper;
  final double dim;
  Map<String, dynamic> toJson() => {
    'mode': mode,
    'wallpaper': wallpaper,
    'customFile': customFile,
    'matchWallpaper': matchWallpaper,
    'seed': seed,
    'customSeed': customSeed,
    'dim': dim,
    'splash': splash,
    'loading': loading,
  };
  factory PulseAppearanceSettings.fromJson(Map<String, dynamic> j) {
    String choice(String key, List<String> options, String fallback) =>
        options.contains(j[key]) ? j[key] as String : fallback;
    int color(String key) =>
        j[key] is int && (j[key] as int) >= 0 && (j[key] as int) <= 0xffffffff
        ? j[key] as int
        : 0xff00bfa6;
    final file = j['customFile'];
    return PulseAppearanceSettings(
      mode: choice('mode', ['dark', 'light', 'system'], 'dark'),
      wallpaper:
          j['wallpaper'] is int &&
              (j['wallpaper'] as int) >= 0 &&
              (j['wallpaper'] as int) < pulseWallpaperNames.length
          ? j['wallpaper'] as int
          : 0,
      customFile:
          file is String && RegExp(r'^[a-zA-Z0-9_-]+\.png$').hasMatch(file)
          ? file
          : null,
      matchWallpaper: j['matchWallpaper'] is bool
          ? j['matchWallpaper'] as bool
          : true,
      seed: color('seed'),
      customSeed: color('customSeed'),
      dim: j['dim'] is num && (j['dim'] as num).isFinite
          ? (j['dim'] as num).toDouble().clamp(0, .8)
          : .25,
      splash: choice('splash', ['glow', 'minimal', 'wave'], 'minimal'),
      loading: choice('loading', ['pulse', 'orbit', 'dots'], 'pulse'),
    );
  }
  PulseAppearanceSettings copy({
    String? mode,
    int? wallpaper,
    String? customFile,
    bool clearCustom = false,
    bool? matchWallpaper,
    int? seed,
    int? customSeed,
    double? dim,
    String? splash,
    String? loading,
  }) => PulseAppearanceSettings(
    mode: mode ?? this.mode,
    wallpaper: wallpaper ?? this.wallpaper,
    customFile: clearCustom ? null : customFile ?? this.customFile,
    matchWallpaper: matchWallpaper ?? this.matchWallpaper,
    seed: seed ?? this.seed,
    customSeed: customSeed ?? this.customSeed,
    dim: dim ?? this.dim,
    splash: splash ?? this.splash,
    loading: loading ?? this.loading,
  );
}
