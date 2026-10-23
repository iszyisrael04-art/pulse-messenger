import 'package:flutter/material.dart';
import 'presence.dart';

class PulseOnlineIndicator extends StatefulWidget {
  const PulseOnlineIndicator({
    super.key,
    required this.presence,
    required this.userId,
    required this.child,
  });
  final PulsePresence presence;
  final String userId;
  final Widget child;
  @override
  State<PulseOnlineIndicator> createState() => _PulseOnlineIndicatorState();
}

class _PulseOnlineIndicatorState extends State<PulseOnlineIndicator> {
  @override
  void initState() {
    super.initState();
    widget.presence.watch(widget.userId);
  }

  @override
  void didUpdateWidget(PulseOnlineIndicator old) {
    super.didUpdateWidget(old);
    if (old.presence != widget.presence || old.userId != widget.userId) {
      old.presence.unwatch(old.userId);
      widget.presence.watch(widget.userId);
    }
  }

  @override
  void dispose() {
    widget.presence.unwatch(widget.userId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.presence,
    child: widget.child,
    builder: (_, child) => Stack(
      clipBehavior: Clip.none,
      children: [
        child!,
        if (widget.presence.statuses[widget.userId]?.online(DateTime.now()) ==
            true)
          Positioned(
            right: 0,
            bottom: 0,
            child: Semantics(
              label: 'Online now',
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xff26ce85),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class PulsePresenceLabel extends StatefulWidget {
  const PulsePresenceLabel({
    super.key,
    required this.presence,
    required this.userId,
  });
  final PulsePresence presence;
  final String userId;
  @override
  State<PulsePresenceLabel> createState() => _PulsePresenceLabelState();
}

class _PulsePresenceLabelState extends State<PulsePresenceLabel> {
  @override
  void initState() {
    super.initState();
    widget.presence.watch(widget.userId);
  }

  @override
  void didUpdateWidget(PulsePresenceLabel old) {
    super.didUpdateWidget(old);
    if (old.presence != widget.presence || old.userId != widget.userId) {
      old.presence.unwatch(old.userId);
      widget.presence.watch(widget.userId);
    }
  }

  @override
  void dispose() {
    widget.presence.unwatch(widget.userId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.presence,
    builder: (_, __) {
      final status = widget.presence.statuses[widget.userId];
      final now = DateTime.now();
      final label = status?.label(now) ?? '';
      if (label.isEmpty) return const SizedBox.shrink();
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: status!.online(now)
              ? const Color(0xff26ce85)
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    },
  );
}

class PulsePresenceSettings extends StatefulWidget {
  const PulsePresenceSettings({super.key, required this.presence});
  final PulsePresence presence;
  @override
  State<PulsePresenceSettings> createState() => _PulsePresenceSettingsState();
}

class _PulsePresenceSettingsState extends State<PulsePresenceSettings> {
  bool saving = false;
  String? error;
  Future<void> change(bool value) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.presence.setSharing(value);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not save your privacy setting. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Active status')),
    body: AnimatedBuilder(
      animation: widget.presence,
      builder: (_, __) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.circle, color: Color(0xff26ce85), size: 42),
          const SizedBox(height: 20),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share active status'),
            subtitle: const Text(
              'Let people you chat with and approved followers see when you are online or last active.',
            ),
            value: widget.presence.sharing ?? false,
            onChanged: saving || widget.presence.sharing == null
                ? null
                : change,
          ),
          const SizedBox(height: 12),
          const Text(
            'Turning this off hides both your online status and last seen. Blocked accounts cannot see your activity.',
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (widget.presence.sharing == null)
            TextButton(
              onPressed: () => widget.presence.refresh(),
              child: const Text('Load current setting'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
        ],
      ),
    ),
  );
}
