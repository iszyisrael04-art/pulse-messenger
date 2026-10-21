import 'package:flutter/material.dart';
import 'interests.dart';
import 'social_repository.dart';

class PulseInterestPicker extends StatefulWidget {
  const PulseInterestPicker({super.key, required this.store});
  final SocialStore store;
  @override
  State<PulseInterestPicker> createState() => _PulseInterestPickerState();
}

class _PulseInterestPickerState extends State<PulseInterestPicker> {
  late final Set<String> selected;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    selected = widget.store.interests.toSet();
  }

  Future<void> save({bool skip = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.saveInterests(skip ? [] : selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Your interests could not be saved. Check the connection and retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Make Pulse yours')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'What do you like watching?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose up to 8 interests for For You. You can change them later. Friends stays separate.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (final topic in pulseInterestTopics.entries)
                    FilterChip(
                      label: Text(topic.value),
                      selected: selected.contains(topic.key),
                      onSelected: busy
                          ? null
                          : (on) => setState(() {
                              if (!on)
                                selected.remove(topic.key);
                              else if (selected.length < 8)
                                selected.add(topic.key);
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: busy || selected.isEmpty ? null : save,
                child: Text(busy ? 'Saving…' : 'Start exploring'),
              ),
              TextButton(
                onPressed: busy ? null : () => save(skip: true),
                child: const Text('Explore without choosing'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
