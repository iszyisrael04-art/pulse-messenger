import 'package:flutter/material.dart';
import 'social_repository.dart';
import 'premium_service.dart';

const oversizePremiumMessage =
    'Your file is over 500MB. Please upgrade to Premium to continue.';

class PulsePremiumPage extends StatefulWidget {
  const PulsePremiumPage({super.key, required this.store, this.reason});
  final SocialStore store;
  final String? reason;
  @override
  State<PulsePremiumPage> createState() => _PulsePremiumPageState();
}

class _PulsePremiumPageState extends State<PulsePremiumPage> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> redeem() async {
    if (code.text.trim().isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await redeemPulseCode(widget.store.repo, code.text);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = redeemError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pulse Premium')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            const Icon(Icons.workspace_premium, size: 72, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              widget.reason ?? 'Make more of Pulse.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Premium includes larger uploads, animated GIF profile pictures, eight profile backgrounds, a Profile Signal card, per-chat bubble styles, up to 20 saved quick replies and a profile badge. The planned subscription is \$3/month. Payments are not connected yet. You can redeem an eligible code below.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: code,
              enabled: !busy,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Redeem code'),
            ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : redeem,
              child: Text(busy ? 'Checking…' : 'Redeem code'),
            ),
          ],
        ),
      ),
    ),
  );
}
