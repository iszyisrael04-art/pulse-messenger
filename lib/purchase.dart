import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'repository.dart' hide Row;
import 'creator_products.dart';

class PulsePurchasePage extends StatefulWidget {
  const PulsePurchasePage({
    super.key,
    required this.repo,
    required this.sku,
    required this.title,
    required this.usdCents,
  });
  final PulseRepository repo;
  final String sku, title;
  final int usdCents;
  @override
  State<PulsePurchasePage> createState() => _PulsePurchasePageState();
}

class _PulsePurchasePageState extends State<PulsePurchasePage> {
  final email = TextEditingController();
  final order = const Uuid().v4();
  bool busy = false, started = false, paid = false;
  String message =
      'The final amount and currency appear on Squad checkout. Do not pay if they differ.';
  @override
  void initState() {
    super.initState();
    email.text = widget.repo.db.auth.currentUser?.email ?? '';
  }

  Future<void> run(bool verify) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!verify && email.text.trim().isEmpty) {
        setState(() => message = 'Enter a receipt email.');
        return;
      }
      if (!verify) setState(() => started = true);
      final r = await widget.repo.db.functions
          .invoke(
            'pulse-payments',
            body: verify
                ? {'action': 'verify', 'reference': order}
                : {
                    'action': 'checkout',
                    'order_id': order,
                    'sku': widget.sku,
                    'email': email.text.trim(),
                  },
          )
          .timeout(const Duration(seconds: 25));
      final data = Map<String, dynamic>.from(r.data as Map);
      if (data['paid'] == true) {
        await widget.repo.refreshCreatorAccess();
        if (mounted)
          setState(() {
            paid = true;
            message = 'Payment verified and purchase delivered.';
          });
      } else if (verify) {
        if (mounted)
          setState(
            () => message =
                data['status']?.toString() ??
                'Not confirmed. Do not pay again while checking.',
          );
      } else {
        final url = Uri.parse(data['checkout_url'] as String);
        if (url.scheme != 'https' ||
            url.host != 'pay.squadco.com' ||
            url.userInfo.isNotEmpty ||
            url.hasPort)
          throw const FormatException('Unexpected checkout URL');
        if (!mounted) return;
        final opened = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        if (mounted)
          setState(
            () => message = opened
                ? 'Complete checkout in your browser, return and verify. If checking takes time, do not pay again.'
                : 'Could not open checkout. You can still verify an existing payment.',
          );
      }
    } on FunctionException catch (e) {
      if (mounted)
        setState(
          () => message = e.details is Map
              ? (e.details['error'] ?? 'Checkout unavailable').toString()
              : 'Checkout unavailable.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => message =
              'Could not confirm this payment. Verify before trying another payment.',
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
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          pulseUsd(widget.usdCents),
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Charged in USD. This is a one-time payment; time-limited Boost plans do not automatically renew.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: email,
          enabled: !busy && !started,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Receipt email',
            helperText: 'Shared with Squad when checkout starts.',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || paid ? null : () => run(false),
          child: const Text('Continue to Squad'),
        ),
        if (started)
          OutlinedButton(
            onPressed: busy || paid ? null : () => run(true),
            child: const Text('Verify payment'),
          ),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 20),
        Text(message),
        const SizedBox(height: 20),
        SelectableText('Order reference: $order'),
        const Text(
          'Keep this reference if you need payment support. Never share card details or banking OTPs in chat.',
        ),
      ],
    ),
  );
}
