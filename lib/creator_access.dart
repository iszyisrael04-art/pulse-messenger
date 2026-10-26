import 'regional_pricing.dart';
import 'package:flutter/material.dart';
import 'creator_products.dart';
import 'payment_test.dart';
import 'purchase.dart';
import 'social_repository.dart';

class PulseCreatorAccessPage extends StatefulWidget {
  const PulseCreatorAccessPage({super.key, required this.store, this.reason});
  final SocialStore store;
  final String? reason;
  @override
  State<PulseCreatorAccessPage> createState() => _PulseCreatorAccessPageState();
}

class _PulseCreatorAccessPageState extends State<PulseCreatorAccessPage> {
  Map<String, dynamic>? access;
  String? error;
  bool loading = false, paymentsEnabled = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.store.repo.rpc('creator_access', {});
      await widget.store.repo.refreshCreatorAccess();
      try {
        final status = await widget.store.repo.db.functions.invoke(
          'pulse-payments',
          body: {'action': 'health'},
        );
        paymentsEnabled =
            status.data is Map && status.data['purchases_enabled'] == true;
      } catch (_) {
        paymentsEnabled = false;
      }
      if (mounted)
        setState(() => access = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = access;
    final products = (data?['products'] as List? ?? []).cast<Map>();
    final purchases = (data?['purchases'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: const Text('Animated profile & Boost')),
      body: PulseRegionalPrices(
        repo: widget.store.repo,
        builder: (context, prices, currencyPicker) => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            currencyPicker,
            if (widget.reason != null)
              Text(
                widget.reason!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 16),
            const Text(
              'Make your profile move',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'GIFs and videos trimmed to five seconds. One unlock covers both.',
            ),
            if (data?['motion_free'] == true)
              const ListTile(
                leading: Icon(Icons.check_circle),
                title: Text('Permanently free for your account'),
                subtitle: Text('Your account has owner access.'),
              )
            else if (data?['motion'] == true)
              const ListTile(
                leading: Icon(Icons.check_circle),
                title: Text('Animated profiles unlocked'),
              ),
            for (final product in products.where((p) => p['sku'] == 'motion'))
              productCard(product, prices, motion: true),
            const SizedBox(height: 28),
            const Text(
              'Boost your account',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Promote your public videos to more Pulse viewers. Each video has its own view limit during your plan period. Delivery depends on audience availability; the limit is not a guaranteed result.',
            ),
            const SizedBox(height: 12),
            for (final product in products.where((p) => p['sku'] != 'motion'))
              productCard(product, prices),
            if (data != null) ...[
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.info_outline),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  paymentsEnabled
                      ? 'Secure checkout'
                      : 'Payment setup pending',
                ),
                subtitle: Text(
                  paymentsEnabled
                      ? 'Review the exact total and currency before paying. Boost plans do not automatically renew.'
                      : 'Real purchases are disabled until the live payment provider is configured and tested.',
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PulsePaymentTestPage(repo: widget.store.repo),
                ),
              ),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Test checkout (no real money)'),
            ),
            if (purchases.isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                'Your purchases',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final purchase in purchases)
                ListTile(
                  title: Text(
                    products
                            .where((p) => p['sku'] == purchase['sku'])
                            .firstOrNull?['title']
                            ?.toString() ??
                        purchase['sku'].toString(),
                  ),
                  subtitle: Text(
                    purchase['ends_at'] == null
                        ? 'One-time unlock'
                        : 'Ends ${purchase['ends_at'].toString().split('T').first} · ${purchase['delivered_views']} qualified views delivered',
                  ),
                ),
            ],
            if (loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: loading ? null : load,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget productCard(Map product, PulseRegionalPrice prices, {bool motion = false}) {
    final owned = motion && access?['motion'] == true;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              motion
                  ? Icons.motion_photos_on_outlined
                  : Icons.trending_up_rounded,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              product['title'].toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              '${prices.label(product['usd_cents'] as int)} · ${pulseProductPeriod(product['period'] as String)}',
            ),
            if (!motion)
              Text(
                'Up to ${pulseViewCap(product['view_cap'] as int)} views per video',
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: owned || !paymentsEnabled
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PulsePurchasePage(
                            repo: widget.store.repo,
                            sku: product['sku'] as String,
                            title: product['title'] as String,
                            usdCents: product['usd_cents'] as int,
                          ),
                        ),
                      );
                      await load();
                    },
              child: Text(
                owned
                    ? 'Unlocked'
                    : paymentsEnabled
                    ? 'Continue to checkout'
                    : 'Payment setup pending',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
