import 'dart:async';
import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'mailbox.dart';

class PulseRewardMailButton extends StatefulWidget {
  const PulseRewardMailButton({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseRewardMailButton> createState() => _PulseRewardMailButtonState();
}

class _PulseRewardMailButtonState extends State<PulseRewardMailButton> {
  int unread = 0;
  Timer? timer;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final r = await widget.repo.rpc('reward_mail', {});
      if (mounted) setState(() => unread = (r['unread'] as num).toInt());
    } catch (_) {
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Pulse mail & requests',
    icon: Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: const Icon(Icons.mail_outline),
    ),
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PulseMailbox(repo: widget.repo),
        ),
      );
      load();
    },
  );
}
