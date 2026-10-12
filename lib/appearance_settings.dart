import 'package:flutter/material.dart';
import 'appearance.dart';
import 'appearance_model.dart';

class PulseAppearancePage extends StatefulWidget {
  const PulseAppearancePage({super.key});
  @override
  State<PulseAppearancePage> createState() => _PulseAppearancePageState();
}

class _PulseAppearancePageState extends State<PulseAppearancePage> {
  final appearance = PulseAppearance.instance;
  bool busy = false;
  String? error;
  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : 'Could not save appearance. Please retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void previewSplash() => showDialog<void>(
    context: context,
    builder: (c) => Dialog.fullscreen(
      child: Stack(
        children: [
          const PulseSplash(message: 'Splash preview'),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Close preview',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appearance,
    builder: (_, __) {
      final settings = appearance.settings;
      return Scaffold(
        appBar: AppBar(title: const Text('Themes & wallpapers')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Make PULSE yours',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'These choices are saved for your account on this device.',
                ),
                const SizedBox(height: 20),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'light',
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                    ButtonSegment(
                      value: 'system',
                      label: Text('System'),
                      icon: Icon(Icons.settings_suggest),
                    ),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: busy
                      ? null
                      : (v) => change(
                          () => appearance.set(settings.copy(mode: v.first)),
                        ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: PulseWallpaper(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Your conversations, your style.',
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'Looks good!',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Match theme to wallpaper'),
                  subtitle: const Text('Use wallpaper colors across the app.'),
                  value: settings.matchWallpaper,
                  onChanged: busy
                      ? null
                      : (v) => change(
                          () =>
                              appearance.set(settings.copy(matchWallpaper: v)),
                        ),
                ),
                if (!settings.matchWallpaper)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final color in pulseWallpaperColors.take(12))
                        Semantics(
                          label: 'Accent color',
                          selected: settings.seed == color,
                          button: true,
                          child: InkWell(
                            onTap: busy
                                ? null
                                : () => change(
                                    () => appearance.set(
                                      settings.copy(seed: color),
                                    ),
                                  ),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(color),
                                border: Border.all(
                                  color: settings.seed == color
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: settings.seed == color
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Chat wallpaper',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => change(appearance.choosePhoto),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from your photos'),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (c, box) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: box.maxWidth > 600 ? 4 : 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: pulseWallpaperNames.length,
                    itemBuilder: (c, i) => Semantics(
                      selected:
                          settings.customFile == null &&
                          settings.wallpaper == i,
                      button: true,
                      label: pulseWallpaperNames[i],
                      child: InkWell(
                        onTap: busy
                            ? null
                            : () => change(
                                () => appearance.set(
                                  settings.copy(
                                    wallpaper: i,
                                    clearCustom: true,
                                  ),
                                ),
                              ),
                        borderRadius: BorderRadius.circular(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: PulseWallpaper(
                            index: i,
                            dim: 0,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: .9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      pulseWallpaperNames[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (settings.customFile == null &&
                                    settings.wallpaper == i)
                                  const Positioned(
                                    right: 10,
                                    top: 10,
                                    child: Icon(Icons.check_circle),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Wallpaper dimming'),
                Slider(
                  value: settings.dim,
                  max: .8,
                  divisions: 16,
                  label: '${(settings.dim * 100).round()}%',
                  onChanged: busy
                      ? null
                      : (v) =>
                            change(() => appearance.set(settings.copy(dim: v))),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Splash style',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final style in ['glow', 'minimal', 'wave'])
                      ChoiceChip(
                        label: Text(style),
                        selected: settings.splash == style,
                        onSelected: busy
                            ? null
                            : (_) => change(
                                () => appearance.set(
                                  settings.copy(splash: style),
                                ),
                              ),
                      ),
                  ],
                ),
                TextButton.icon(
                  onPressed: previewSplash,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview splash screen'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading style',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final style in ['pulse', 'orbit', 'dots'])
                      ChoiceChip(
                        label: Text(style),
                        selected: settings.loading == style,
                        onSelected: busy
                            ? null
                            : (_) => change(
                                () => appearance.set(
                                  settings.copy(loading: style),
                                ),
                              ),
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: PulseLoader(size: 48)),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => change(
                          () => appearance.set(PulseAppearanceSettings()),
                        ),
                  child: const Text('Restore Pulse defaults'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
