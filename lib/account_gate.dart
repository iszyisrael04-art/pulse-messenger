import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'appeals.dart';

class PulseAccountGate extends StatefulWidget {
  const PulseAccountGate({
    super.key,
    required this.child,
    required this.onRestricted,
    this.appealMode = false,
  });
  final Widget child;
  final Future<void> Function(Map<String, dynamic>) onRestricted;
  final bool appealMode;
  @override
  State<PulseAccountGate> createState() => _PulseAccountGateState();
}

class _PulseAccountGateState extends State<PulseAccountGate>
    with WidgetsBindingObserver {
  Map<String, dynamic>? status;
  bool busy = false, leaving = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (busy || leaving) return;
    busy = true;
    try {
      final r = await Supabase.instance.client.rpc('pulse_account_status');
      if (!mounted) return;
      final s = Map<String, dynamic>.from(r as Map);
      setState(() {
        status = s;
        error = null;
      });
      if (s['active'] != true && !widget.appealMode) {
        leaving = true;
        await widget.onRestricted(s);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Account access could not be checked. Check your connection; this build also needs the approved backend upgrade.',
        );
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status?['active'] == true) return widget.child;
    if (status != null && widget.appealMode)
      return Scaffold(
        appBar: AppBar(
          title: const Text('Restricted account'),
          actions: [
            IconButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 72, color: Colors.red),
              const Text('Account access is restricted'),
              Text(status!['reason'] ?? ''),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PulseAppealPage()),
                ),
                child: const Text('Submit video appeal'),
              ),
            ],
          ),
        ),
      );
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) const CircularProgressIndicator(),
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: load, child: const Text('Retry')),
                TextButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PulseRestrictionNotice extends StatelessWidget {
  const PulseRestrictionNotice({
    super.key,
    required this.status,
    required this.onAppeal,
    required this.onBack,
  });
  final Map status;
  final VoidCallback onAppeal, onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 84, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                status['state'] == 'banned'
                    ? 'This account is banned'
                    : 'This account is suspended',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You cannot access this account. You have been signed out.',
                textAlign: TextAlign.center,
              ),
              Text(status['reason'] ?? ''),
              if (status['until'] != null)
                Text('Suspended until ${status['until']}'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAppeal,
                child: const Text('Sign in for a video appeal'),
              ),
              TextButton(
                onPressed: onBack,
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
