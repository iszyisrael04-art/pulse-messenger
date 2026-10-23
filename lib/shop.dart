import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'social_repository.dart';
import 'creator_access.dart';
import 'creator_products.dart';
import 'payment_test.dart';
import 'purchase.dart';

class PulseShopPage extends StatefulWidget {
  const PulseShopPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseShopPage> createState() => _PulseShopPageState();
}

class _PulseShopPageState extends State<PulseShopPage> {
  Map<String, dynamic>? wallet;
  String? error;
  bool busy = false, paymentsEnabled = false;
  late final store = SocialStore(widget.repo);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.repo.rpc('wallet', {});
      try {
        final status = await widget.repo.db.functions.invoke(
          'pulse-payments',
          body: {'action': 'health'},
        );
        paymentsEnabled =
            status.data is Map && status.data['purchases_enabled'] == true;
      } catch (_) {
        paymentsEnabled = false;
      }
      if (mounted)
        setState(() => wallet = Map<String, dynamic>.from(data as Map));
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pulse shop'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Your wallet',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${wallet?['coins'] ?? '—'} Coins',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Use normal coins to send gifts. Normal coins cannot be withdrawn.',
                  ),
                  const Divider(height: 32),
                  Text(
                    '${wallet?['p_coins'] ?? '—'} P-coins',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Earned when someone sends you a gift. A Rose costs 5 coins and earns you 2 P-coins. 100 P-coins = \$3.',
                  ),
                  const SizedBox(height: 12),
                  const OutlinedButton(
                    onPressed: null,
                    child: Text('Withdraw · payout setup pending'),
                  ),
                  Text(
                    wallet?['cashout_message']?.toString() ??
                        '100 P-coins = \$3. A verified payout service is needed before withdrawals open.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Buy coins',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          for (final pack in wallet?['coin_packs'] as List? ?? [])
            ListTile(
              leading: const Icon(Icons.toll_rounded),
              title: Text('${pack['coins']} coins'),
              subtitle: Text(pulseUsd(pack['usd_cents'] as int)),
              trailing: TextButton(
                onPressed: !paymentsEnabled
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PulsePurchasePage(
                              repo: widget.repo,
                              sku: pack['sku'] as String,
                              title: '${pack['coins']} coins',
                              usdCents: pack['usd_cents'] as int,
                            ),
                          ),
                        );
                        await load();
                      },
                child: Text(paymentsEnabled ? 'Buy' : 'Setup pending'),
              ),
            ),
          const Text(
            'Real coin purchases stay unavailable until verified live checkout is enabled. Sandbox payments never credit coins.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PulseCreatorAccessPage(store: store),
              ),
            ),
            icon: const Icon(Icons.trending_up),
            label: const Text('Boost views & animated profile'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PulsePaymentTestPage(repo: widget.repo),
              ),
            ),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Test checkout · no real money'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Gift collection',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          for (final gift in wallet?['gifts'] as List? ?? [])
            ListTile(
              leading: Text(
                '${gift['emoji']}',
                style: const TextStyle(fontSize: 30),
              ),
              title: Text('${gift['title']}'),
              subtitle: Text(
                '${gift['coins']} coins → ${gift['p_coins']} P-coins for the recipient',
              ),
            ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
