import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'live_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notifications.dart';
import 'push.dart';
import 'repository.dart';

class PulseDiagnosticsPage extends StatefulWidget {
  const PulseDiagnosticsPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseDiagnosticsPage> createState() => _PulseDiagnosticsPageState();
}

class _PulseDiagnosticsPageState extends State<PulseDiagnosticsPage> {
  bool busy = false;
  String result = 'Not checked';
  String liveResult = 'Not checked';
  String get report => [
    'Pulse 0.5.7 private beta',
    'Platform: ${Platform.operatingSystem}',
    'Authenticated: ${widget.repo.db.auth.currentSession != null}',
    'Backend check: $result',
    'Pending messages on this device: ${widget.repo.pending.length}',
    'Local notifications enabled: ${PulseNotifications.instance.enabled}',
    'Firebase client configured: ${PulsePush.instance.configured}',
    'Background push delivery: not verified',
    'LiveKit control check: $liveResult',
    'Real camera/microphone and multi-device media: not verified',
    'End-to-end encryption: not implemented',
  ].join('\n');

  Future<void> check() async {
    if (busy) return;
    setState(() {
      busy = true;
      result = 'Checking…';
    });
    final watch = Stopwatch()..start();
    try {
      final owner = widget.repo.uid;
      await widget.repo.db
          .from('pulse_profiles')
          .select('id')
          .eq('id', owner)
          .single()
          .timeout(const Duration(seconds: 15));
      if (mounted)
        setState(
          () => result =
              'Authenticated profile read succeeded (${watch.elapsedMilliseconds} ms)',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => result =
              'Could not confirm access. Check internet and sign-in status.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkLiveKit() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final response = await widget.repo.db.functions.invoke(
        'pulse-live',
        body: {'action': 'health'},
      );
      final data = response.data;
      if (mounted) setState(() => liveResult = pulseLiveCheckMessage(data));
    } on FunctionException catch (e) {
      if (mounted)
        setState(
          () => liveResult = pulseLiveCheckMessage(e.details, status: e.status),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => liveResult =
              'Could not confirm LiveKit access. Check connectivity, server configuration, and the deployed pulse-live function. Wait before retrying.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnostics')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Check Pulse on this device',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'This report excludes passwords, tokens, email addresses and message content. Nothing is uploaded automatically. A successful connection check does not prove every feature works.',
            ),
            const SizedBox(height: 20),
            SelectableText(report),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : check,
              icon: const Icon(Icons.network_check),
              label: Text(busy ? 'Checking…' : 'Check backend connection'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : checkLiveKit,
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Check LiveKit connection'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Diagnostic report copied.')),
                  );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy report'),
            ),
          ],
        ),
      ),
    ),
  );
}
