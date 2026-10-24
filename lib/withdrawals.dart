import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:url_launcher/url_launcher.dart';
import 'repository.dart' hide Row;
import 'social_repository.dart' show socialError;

class PulseWithdrawalsPage extends StatefulWidget {
  const PulseWithdrawalsPage({
    super.key,
    required this.repo,
    this.admin = false,
  });
  final PulseRepository repo;
  final bool admin;
  @override
  State<PulseWithdrawalsPage> createState() => _PulseWithdrawalsPageState();
}

class _PulseWithdrawalsPageState extends State<PulseWithdrawalsPage> {
  final amount = TextEditingController(text: '100'),
      bank = TextEditingController(),
      account = TextEditingController();
  Map<String, dynamic> info = {};
  Map? quote;
  bool enabled = false, busy = false;
  String? error;
  static const banks = {
    '000013': 'GTBank',
    '000014': 'Access Bank',
    '000015': 'Zenith Bank',
    '000016': 'First Bank',
    '000004': 'UBA',
    '000007': 'Fidelity',
    '000003': 'FCMB',
    '000017': 'Wema Bank',
    '000012': 'Stanbic IBTC',
    '090267': 'Kuda',
  };
  String naira(dynamic value) =>
      '₦${((value as num).toDouble() / 100).toStringAsFixed(2)}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.repo.rpc('withdraw_info', {
        'p_admin': widget.admin,
      });
      final health = await widget.repo.db.functions.invoke(
        'pulse-withdrawals',
        body: {'action': 'health'},
      );
      if (mounted)
        setState(() {
          info = Map<String, dynamic>.from(data as Map);
          enabled = health.data is Map && health.data['enabled'] == true;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String type, {String? id}) async {
    if (busy) return;
    if (['confirm', 'approve', 'decline'].contains(type)) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            type == 'confirm'
                ? 'Confirm withdrawal?'
                : type == 'approve'
                ? 'Approve bank payout?'
                : 'Decline and restore P-coins?',
          ),
          content: Text(
            type == 'confirm'
                ? '${quote?['p_coins']} P-coins will be reserved. ${naira(quote?['net_kobo'] ?? 0)} will be paid to ${quote?['account_name']} after staff approval.'
                : type == 'approve'
                ? 'This sends real money to the bank account already verified for this request. A submitted transfer cannot be cancelled here.'
                : 'Only requests awaiting review can be declined. Reserved P-coins will be restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.repo.db.functions
          .invoke(
            'pulse-withdrawals',
            body: {
              'action': type,
              if (id != null) 'id': id,
              if (type == 'quote') ...{
                'p_coins': int.tryParse(amount.text),
                'bank_code': bank.text.trim(),
                'account_number': account.text.trim(),
              },
            },
          )
          .timeout(const Duration(seconds: 35));
      if (mounted)
        setState(() {
          if (type == 'quote')
            quote = r.data['quote'] as Map;
          else
            quote = null;
          error = r.data['message']?.toString();
        });
    } on FunctionException catch (e) {
      if (mounted)
        setState(
          () => error = e.details is Map
              ? (e.details['error'] ?? 'Withdrawal unavailable').toString()
              : 'Withdrawal unavailable.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not confirm the result. Check the existing request before trying again.',
        );
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (type != 'quote') {
          final message = error;
          await load();
          if (mounted && message != null) setState(() => error = message);
        }
      }
    }
  }

  @override
  void dispose() {
    amount.dispose();
    bank.dispose();
    account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.admin ? 'Payout requests' : 'Withdraw P-coins'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!enabled)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Bank payouts are not enabled. P-coins remain recorded in your wallet.',
              ),
            ),
          ),
        if (!widget.admin) ...[
          Text(
            '${info['available_p_coins'] ?? '—'} P-coins available',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Text(
            '100 P-coins = \$30. Gifts become available after 7 days. Withdrawals are paid in naira after staff review.',
          ),
          const SizedBox(height: 20),
          TextField(
            onChanged: (_) => setState(() => quote = null),
            controller: amount,
            enabled: enabled && !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'P-coins (minimum 100)',
            ),
          ),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Bank'),
            items: [
              ...banks.entries.map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              ),
              const DropdownMenuItem(
                value: 'other',
                child: Text('Other bank · enter NIP code'),
              ),
            ],
            onChanged: !enabled || busy
                ? null
                : (v) {
                    setState(() {
                      bank.text = v == 'other' ? '' : v ?? '';
                      quote = null;
                    });
                  },
          ),
          TextField(
            onChanged: (_) => setState(() => quote = null),
            controller: bank,
            enabled: enabled && !busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Six-digit NIP bank code',
            ),
          ),
          TextField(
            onChanged: (_) => setState(() => quote = null),
            controller: account,
            enabled: enabled && !busy,
            keyboardType: TextInputType.number,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Bank account number',
              helperText:
                  'Sent to Squad for account-name verification when you request a quote.',
            ),
          ),
          FilledButton(
            onPressed: !enabled || busy ? null : () => action('quote'),
            child: const Text('Verify account & get naira quote'),
          ),
          if (quote != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${quote!['account_name']} · ••••••${quote!['account_number'].toString().substring(6)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Gross ${naira(quote!['gross_kobo'])} · fee ${naira(quote!['fee_kobo'])}',
                    ),
                    Text(
                      'Amount sent ${naira(quote!['net_kobo'])}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'This quote expires after 10 minutes and uses a daily reference rate. Check the account name and amount before confirming.',
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://www.exchangerate-api.com'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Rates By Exchange Rate API'),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => action('confirm', id: quote!['id'] as String),
                      child: const Text('Confirm & reserve P-coins'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Withdrawal history',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        for (final request in info['requests'] as List? ?? [])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${request['p_coins']} P-coins · ${naira(request['net_kobo'])}',
                  ),
                  Text('${request['account_name']} · ${request['account']}'),
                  Text('Status: ${request['state']}'),
                  SelectableText('Reference: ${request['id']}'),
                  if (enabled && widget.admin && request['state'] == 'review')
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  'approve',
                                  id: request['id'] as String,
                                ),
                          child: const Text('Approve payout'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  'decline',
                                  id: request['id'] as String,
                                ),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  if (enabled && request['state'] == 'processing')
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              widget.admin ? 'reconcile' : 'status',
                              id: request['id'] as String,
                            ),
                      child: const Text('Check existing transfer'),
                    ),
                ],
              ),
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
      ],
    ),
  );
}
