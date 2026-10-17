import 'package:flutter/material.dart';
import 'profile_rules.dart';
import 'social_repository.dart';
import 'social_premium.dart';

List<Color> pulseBackgroundColors(String style) => switch (style) {
  'aurora' => [const Color(0xff175c66), const Color(0xff553b86)],
  'sunset' => [const Color(0xff9a4c43), const Color(0xff623a75)],
  'ocean' => [const Color(0xff085c78), const Color(0xff123c78)],
  'bloom' => [const Color(0xff783a69), const Color(0xff5b367f)],
  'paper' => [const Color(0xff4c5a55), const Color(0xff33463f)],
  'circuit' => [const Color(0xff164b43), const Color(0xff27375c)],
  _ => [const Color(0xff142a4d), const Color(0xff252238)],
};

class PulseProfileBackdrop extends StatelessWidget {
  const PulseProfileBackdrop({
    super.key,
    required this.style,
    required this.child,
  });
  final String style;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface;
    final colors = pulseBackgroundColors(
      style,
    ).map((c) => Color.alphaBlend(c.withValues(alpha: .16), base)).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: style == 'classic'
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
      ),
      child: child,
    );
  }
}

Future<bool?> editPulseIdentity(
  BuildContext context,
  SocialStore store,
  Map features,
) async {
  if (!store.repo.premiumActive) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PulsePremiumPage(
          store: store,
          reason: 'Unlock profile backgrounds and your Profile Signal.',
        ),
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => _IdentityEditor(store: store, features: features),
  );
}

class _IdentityEditor extends StatefulWidget {
  const _IdentityEditor({required this.store, required this.features});
  final SocialStore store;
  final Map features;
  @override
  State<_IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends State<_IdentityEditor> {
  late final TextEditingController text;
  late String background, mode;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(
      text: widget.features['signal'] as String? ?? '',
    );
    background = widget.features['background'] as String? ?? 'classic';
    mode = widget.features['mode'] as String? ?? 'creating';
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.repo
          .rpc('profile_features_save', {
            'p_background': background,
            'p_signal': text.text.trim(),
            'p_mode': mode,
          })
          .timeout(const Duration(seconds: 15));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not save. Check your connection and that Premium is still active.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Your Pulse identity'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Profile background',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in pulseProfileBackgrounds.entries)
                    ChoiceChip(
                      selected: background == entry.key,
                      label: Text(entry.value),
                      avatar: CircleAvatar(
                        radius: 9,
                        backgroundColor: pulseBackgroundColors(entry.key).first,
                      ),
                      onSelected: busy
                          ? null
                          : (_) => setState(() => background = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Profile Signal',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Tell people what you are creating, learning or available for. Visible with your profile.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                items: [
                  for (final entry in pulseSignalModes.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => mode = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                enabled: !busy,
                maxLength: 120,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Your Signal',
                  hintText: 'Creating my next short film…',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        background = 'classic';
                        text.clear();
                      }),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset preview'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save identity'),
        ),
      ],
    ),
  );
}
