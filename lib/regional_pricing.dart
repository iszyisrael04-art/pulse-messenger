import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'regional_currency_data.dart';

String? pulseCountryCurrency(String? country) =>
    pulseCountryCurrencies[country?.toUpperCase()];

String pulseMoney(num value, String currency) {
  final digits = pulseCurrencyDigits[currency] ?? 2;
  final parts = value.toStringAsFixed(digits).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},',
  );
  final number = digits == 0 ? whole : '$whole.${parts[1]}';
  return currency == 'NGN' ? '₦$number' : '$currency $number';
}

class PulseRegionalPrice {
  const PulseRegionalPrice({required this.currency, this.ngnRate, this.fx, this.date});
  final String currency;
  final double? ngnRate, fx;
  final String? date;

  factory PulseRegionalPrice.parse(String currency, Map data) {
    final base = data['ngn_per_catalog_usd'];
    final display = data['display'];
    final rate = display is Map && display['currency'] == currency ? display['rate'] : null;
    return PulseRegionalPrice(
      currency: currency,
      ngnRate: data['charge_currency'] == 'NGN' && base is num && base.isFinite && base > 0 ? base.toDouble() : null,
      fx: rate is num && rate.isFinite && rate > 0 ? rate.toDouble() : null,
      date: display is Map ? display['date'] as String? : null,
    );
  }

  String label(int catalogCents) {
    final base = ngnRate;
    if (base == null) return 'Price available at checkout';
    // Match the server's upward rounding to one kobo. Local FX is informational.
    final naira = (catalogCents * base).ceil() / 100;
    if (currency == 'NGN' || fx == null) return pulseMoney(naira, 'NGN');
    return '≈ ${pulseMoney(naira * fx!, currency)}';
  }

  String get explanation => ngnRate == null
      ? 'Connect to load prices. The exact total appears before payment.'
      : currency == 'NGN'
      ? 'Checkout charges NGN. Review the exact total before paying.'
      : fx == null
      ? 'Local conversion unavailable. Showing NGN checkout prices.'
      : 'Estimate · Frankfurter rates${date == null ? '' : ' · $date'}. Checkout charges NGN; your bank sets its conversion and any fees.';
}

/// Device region supplies a default; users can change it without GPS permission.
/// The selected country affects display only and is never a settlement input.
class PulseRegionalPrices extends StatefulWidget {
  const PulseRegionalPrices({super.key, required this.repo, required this.builder});
  final PulseRepository repo;
  final Widget Function(BuildContext, PulseRegionalPrice, Widget) builder;
  @override
  State<PulseRegionalPrices> createState() => _PulseRegionalPricesState();
}

class _PulseRegionalPricesState extends State<PulseRegionalPrices> {
  String? country;
  late PulseRegionalPrice prices;
  int revision = 0;
  bool loading = true;
  static const preferenceKey = 'pulse.shop.country';

  @override
  void initState() {
    super.initState();
    country = WidgetsBinding.instance.platformDispatcher.locales
        .map((l) => l.countryCode)
        .where((c) => pulseCountryCurrency(c) != null)
        .firstOrNull;
    prices = PulseRegionalPrice(currency: pulseCountryCurrency(country) ?? 'NGN');
    restore();
  }

  Future<void> restore() async {
    final initial = revision;
    try {
      final saved = await PulseRepository.vault.read(key: preferenceKey);
      if (!mounted || initial != revision) return;
      if (pulseCountryCurrency(saved) != null) country = saved;
    } catch (_) { /* Region changes still work without preference storage. */ }
    if (mounted && initial == revision) await load();
  }

  Future<void> load() async {
    final token = ++revision;
    final currency = pulseCountryCurrency(country) ?? 'NGN';
    setState(() {
      loading = true;
      prices = PulseRegionalPrice(currency: currency);
    });
    PulseRegionalPrice result = prices;
    try {
      final r = await widget.repo.db.functions.invoke(
        'pulse-payments', body: {'action': 'pricing', 'currency': currency},
      ).timeout(const Duration(seconds: 10));
      if (r.data is Map) result = PulseRegionalPrice.parse(currency, r.data as Map);
    } catch (_) { /* No invented exchange rate or stale charged amount. */ }
    if (mounted && token == revision) setState(() { prices = result; loading = false; });
  }

  void selectCountry() => showCountryPicker(
    context: context,
    showPhoneCode: false,
    onSelect: (value) async {
      country = value.countryCode;
      final loadingPrice = load();
      try {
        await PulseRepository.vault.write(key: preferenceKey, value: country);
      } catch (_) { /* Selection remains usable for this session. */ }
      await loadingPrice;
    },
  );

  @override
  Widget build(BuildContext context) {
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: selectCountry,
              icon: const Icon(Icons.public),
              label: Text('Country / currency: ${country ?? 'Choose'} · ${prices.currency}'),
            ),
            IconButton(
              tooltip: 'Refresh prices',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        Text(prices.explanation, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
    );
    return widget.builder(context, prices, controls);
  }
}
