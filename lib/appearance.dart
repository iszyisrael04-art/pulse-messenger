import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'appearance_model.dart';
import 'brand.dart';

const pulseWallpaperColors = <int>[
  0xff00bfa6,
  0xff8c63ef,
  0xff168ddb,
  0xffed7858,
  0xffcc951d,
  0xffd75c99,
  0xff368764,
  0xff46b8d0,
  0xff526997,
  0xffa486d4,
  0xffe69b73,
  0xff89ac24,
  0xff6658bb,
  0xffc64065,
  0xffb39768,
  0xff38b9a0,
  0xff697e8e,
  0xff425ce2,
  0xff05a9b4,
  0xff6f7880,
];

class PulseAppearance extends ChangeNotifier {
  static final instance = PulseAppearance();
  static const vault = FlutterSecureStorage();
  PulseAppearanceSettings settings = PulseAppearanceSettings();
  String account = 'guest';
  Directory? directory;
  bool ready = false;
  int generation = 0;
  Future<void> writes = Future<void>.value();
  File? get custom => settings.customFile == null || directory == null
      ? null
      : File('${directory!.path}/${settings.customFile}');
  Color get seed => Color(
    settings.matchWallpaper
        ? settings.customFile != null
              ? settings.customSeed
              : pulseWallpaperColors[settings.wallpaper]
        : settings.seed,
  );
  ThemeMode get mode => settings.mode == 'system'
      ? ThemeMode.system
      : settings.mode == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;
  Future<void> restoreBootStyle() async {
    try {
      final raw = await vault.read(key: 'pulse.appearance.boot');
      if (raw != null)
        settings = PulseAppearanceSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        ).copy(clearCustom: true, matchWallpaper: false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> load(String? uid) async {
    final own = ++generation;
    account = uid ?? 'guest';
    ready = false;
    settings = PulseAppearanceSettings();
    directory = null;
    notifyListeners();
    final current = account;
    try {
      final dir = await getApplicationSupportDirectory();
      final target = Directory('${dir.path}/pulse-wallpapers/$current');
      await target.create(recursive: true);
      await writes.catchError((_) {});
      final raw = await vault.read(key: 'pulse.appearance.$current');
      var next = PulseAppearanceSettings();
      if (raw != null)
        next = PulseAppearanceSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      if (next.customFile != null &&
          !await File('${target.path}/${next.customFile}').exists())
        next = next.copy(clearCustom: true);
      if (own != generation) return;
      directory = target;
      settings = next;
    } catch (_) {
      /* Use readable defaults if a local preference is corrupt. */
    }
    if (own == generation) {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> set(PulseAppearanceSettings next) async {
    settings = next;
    notifyListeners();
    final key = 'pulse.appearance.$account', data = jsonEncode(next.toJson());
    final boot = jsonEncode(
      next
          .copy(clearCustom: true, matchWallpaper: false, seed: seed.toARGB32())
          .toJson(),
    );
    final job = writes.catchError((_) {}).then((_) async {
      await vault.write(key: key, value: data);
      await vault.write(key: 'pulse.appearance.boot', value: boot);
    });
    writes = job;
    await job;
  }

  Future<void> choosePhoto() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (selected?.path == null) return;
    final current = generation;
    final source = File(selected!.path!);
    if (await source.length() > 30 * 1024 * 1024)
      throw const FormatException('Choose a wallpaper smaller than 30 MB.');
    if (directory == null)
      throw const FormatException('Local storage unavailable. Restart Pulse.');
    final buffer = await ui.ImmutableBuffer.fromFilePath(source.path);
    ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      buffer.dispose();
      throw const FormatException(
        'This photo format cannot be used as wallpaper.',
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    File? saved;
    try {
      final scale = math.min(
        1.0,
        1920 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null)
        throw const FormatException('Image could not be prepared.');
      if (current != generation) return;
      final name = '${const Uuid().v4()}.png';
      saved = File('${directory!.path}/$name');
      await saved.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(
          FileImage(saved),
          width: 64,
          height: 64,
          policy: ResizeImagePolicy.fit,
        ),
      );
      if (current != generation) {
        await saved.delete();
        return;
      }
      final old = custom;
      await set(
        settings.copy(customFile: name, customSeed: scheme.primary.toARGB32()),
      );
      if (old != null && old.path != saved.path && await old.exists())
        await old.delete();
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xff0d1015)
          : const Color(0xfff7f8fa),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .35),
        thickness: .6,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: scheme.primaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: scheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class PulseWallpaper extends StatelessWidget {
  const PulseWallpaper({
    super.key,
    required this.child,
    this.index,
    this.photo,
    this.dim,
  });
  final Widget child;
  final int? index;
  final File? photo;
  final double? dim;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: PulseAppearance.instance,
    builder: (_, __) {
      final a = PulseAppearance.instance;
      final file = photo ?? (index == null ? a.custom : null);
      final color = Color(pulseWallpaperColors[index ?? a.settings.wallpaper]);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: dark ? .38 : .14),
                    Theme.of(context).colorScheme.surface,
                    color.withValues(alpha: dark ? .20 : .08),
                  ],
                ),
              ),
              child: CustomPaint(
                painter: _WallpaperPainter(
                  color,
                  index ?? a.settings.wallpaper,
                ),
              ),
            ),
          ),
          if (file != null)
            Image(
              image: ResizeImage(
                FileImage(file),
                width: 1080,
                height: 1920,
                policy: ResizeImagePolicy.fit,
              ),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ColoredBox(
            color: (dark ? Colors.black : Colors.white).withValues(
              alpha: dim ?? a.settings.dim,
            ),
          ),
          child,
        ],
      );
    },
  );
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.color, this.index);
  final Color color;
  final int index;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final random = math.Random(index + 71);
    for (var i = 0; i < 24; i++) {
      final x = random.nextDouble() * s.width,
          y = random.nextDouble() * s.height,
          r = 20 + random.nextDouble() * 100;
      if (index % 4 == 0) {
        c.drawCircle(Offset(x, y), r, p);
      } else if (index % 4 == 1) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: r, height: r),
            Radius.circular(r / 4),
          ),
          p,
        );
      } else if (index % 4 == 2) {
        final path = Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(s.width / 2, y - r, s.width, y + r);
        c.drawPath(path, p);
      } else {
        c.drawLine(Offset(x, y), Offset(x + r, y - r), p);
        c.drawCircle(Offset(x, y), 3, p);
      }
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) =>
      old.color != color || old.index != index;
}

class PulseLoader extends StatefulWidget {
  const PulseLoader({super.key, this.size = 36});
  final double size;
  @override
  State<PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<PulseLoader>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
      animation.value = .5;
    } else {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([animation, PulseAppearance.instance]),
    builder: (_, __) => SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _LoaderPainter(
          animation.value,
          PulseAppearance.instance.settings.loading,
          Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.t, this.style, this.color);
  final double t;
  final String style;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color;
    final center = s.center(Offset.zero);
    if (style == 'dots') {
      for (var i = 0; i < 3; i++) {
        p.color = color.withValues(
          alpha: .35 + .65 * (.5 + .5 * math.sin(t * math.pi * 2 - i)),
        );
        c.drawCircle(
          Offset(s.width * (.22 + i * .28), s.height / 2),
          s.width * .07,
          p,
        );
      }
    } else if (style == 'orbit') {
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 3;
      p.color = color.withValues(alpha: .2);
      c.drawCircle(center, s.width * .35, p);
      p.color = color;
      c.drawArc(
        Rect.fromCircle(center: center, radius: s.width * .35),
        t * math.pi * 2,
        math.pi * 1.1,
        false,
        p,
      );
    } else {
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2;
      p.color = color.withValues(alpha: 1 - t);
      c.drawCircle(center, s.width * (.12 + .35 * t), p);
      p.style = PaintingStyle.fill;
      p.color = color;
      c.drawCircle(center, s.width * (.1 + .03 * math.sin(t * math.pi * 2)), p);
    }
  }

  @override
  bool shouldRepaint(_LoaderPainter o) =>
      o.t != t || o.style != style || o.color != color;
}

class PulseSplash extends StatefulWidget {
  const PulseSplash({super.key, this.message = 'Getting things ready'});
  final String message;
  @override
  State<PulseSplash> createState() => _PulseSplashState();
}

class _PulseSplashState extends State<PulseSplash>
    with SingleTickerProviderStateMixin {
  late final reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      reveal.value = 1;
    } else if (reveal.status == AnimationStatus.dismissed) {
      reveal.forward();
    }
  }

  @override
  void dispose() {
    reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([reveal, PulseAppearance.instance]),
    builder: (_, __) {
      final cs = Theme.of(context).colorScheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final style = PulseAppearance.instance.settings.splash;
      final progress = Curves.easeOutCubic.transform(reveal.value);
      return Scaffold(
        backgroundColor: dark
            ? const Color(0xff080b0f)
            : const Color(0xfff8f9fc),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (c, box) => Stack(
              children: [
                if (style == 'glow')
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: box.maxHeight * .36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.primary.withValues(alpha: 0),
                            cs.primary.withValues(alpha: .07),
                          ],
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - progress)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedPulseFavicon(
                            size: style == 'minimal' ? 80 : 96,
                          ),
                          const SizedBox(height: 22),
                          PulseWordmark(size: 54, color: cs.onSurface),
                          const SizedBox(height: 10),
                          Text(
                            'Your people. Your world.',
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant,
                              letterSpacing: .2,
                            ),
                          ),
                          if (style == 'wave')
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Container(
                                width: 44,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 32,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PulseLoader(size: 26),
                      const SizedBox(height: 12),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
