import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/regional_pricing.dart';
import 'package:pulse_messenger/regional_currency_data.dart';

void main() {
  test('Country currencies include regional changes and shared currencies', () {
    expect(pulseCountryCurrencies.length, greaterThan(240));
    expect(pulseCountryCurrency('NG'), 'NGN');
    expect(pulseCountryCurrency('gb'), 'GBP');
    expect(pulseCountryCurrency('BG'), 'EUR');
    expect(pulseCountryCurrency('JP'), 'JPY');
    expect(pulseCountryCurrency('SN'), 'XOF');
    expect(pulseCountryCurrency('ZZ'), isNull);
  });
  test('Local display never substitutes an unverified settlement amount', () {
    final ngn = PulseRegionalPrice.parse('NGN', {'charge_currency':'NGN', 'ngn_per_catalog_usd':450});
    expect(ngn.label(100), '₦450.00');
    expect(ngn.label(1000), '₦4,500.00');
    final usd = PulseRegionalPrice.parse('USD', {
      'charge_currency':'NGN', 'ngn_per_catalog_usd':450,
      'display':{'currency':'USD', 'rate':0.0007, 'date':'2026-10-26'},
    });
    expect(usd.label(100), '≈ USD 0.32');
    expect(usd.explanation, contains('Checkout charges NGN'));
    final unavailable = PulseRegionalPrice.parse('JPY', {'charge_currency':'NGN', 'ngn_per_catalog_usd':450});
    expect(unavailable.label(100), '₦450.00');
    expect(unavailable.explanation, contains('unavailable'));
    expect(const PulseRegionalPrice(currency:'USD').label(100), 'Price available at checkout');
    expect(pulseMoney(199.5, 'JPY'), 'JPY 200');
    expect(pulseMoney(1.1234, 'KWD'), 'KWD 1.123');
  });
}
