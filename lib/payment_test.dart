import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:url_launcher/url_launcher.dart';
import 'repository.dart';
import 'payment_checkout.dart';

/// Sandbox transactions never credit coins or unlock real purchases.
class PulsePaymentTestPage extends StatefulWidget {
  const PulsePaymentTestPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulsePaymentTestPage> createState() => _PulsePaymentTestPageState();
}

class _PulsePaymentTestPageState extends State<PulsePaymentTestPage> {
  final email = TextEditingController();
  String? reference;
  String result =
      'No real money is charged. This does not unlock paid features.';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    email.text = widget.repo.db.auth.currentUser?.email ?? '';
  }

  Future<void> run({bool verify = false}) async {
    if (busy) return;
    if (!verify &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() => result = 'Enter a valid email for the test receipt.');
      return;
    }
    setState(() => busy = true);
    try {
      final response = await widget.repo.db.functions
          .invoke(
            'pulse-payments',
            body: verify
                ? {'action': 'verify-test', 'reference': reference}
                : {'action': 'start-test', 'email': email.text.trim()},
          )
          .timeout(const Duration(seconds: 25));
      final data = Map<String, dynamic>.from(response.data as Map);
      if (verify) {
        if (mounted) setState(() => result = data['status'].toString());
      } else {
        if (!mounted) return;
        setState(() => reference = data['reference'] as String);
        final url = pulsePaymentCheckout(data['checkout_url'] as String, test: true);
        if (url == null) throw const FormatException('Unexpected checkout address');
        final opened = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        if (mounted)
          setState(
            () => result = opened
                ? 'Complete the sandbox checkout, then return and tap Verify test. Use the provider’s test details only.'
                : 'Could not open checkout. Retry when your browser is available.',
          );
      }
    } on FunctionException catch (e) {
      final details = e.details;
      if (mounted)
        setState(
          () => result = details is Map
              ? (details['error'] ?? 'Payment test unavailable.').toString()
              : 'Payment test unavailable. Please retry.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => result =
              'Could not complete the test. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment sandbox test')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.science_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Sandbox only',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Simulated ₦100 checkout. This amount is for testing, not the price of an animated profile or Boost. Your receipt email will be sent to the selected payment provider when you start.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Test receipt email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => run(),
          child: const Text('Open sandbox checkout'),
        ),
        if (reference != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy ? null : () => run(verify: true),
            child: const Text('Verify test'),
          ),
        ],
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(result),
        const SizedBox(height: 20),
        const Text(
          'Never enter a real card, bank PIN or banking OTP in this sandbox test. Simulated tests never grant coins or paid features.',
        ),
      ],
    ),
  );
}
