import 'package:flutter_test/flutter_test.dart';
import '../lib/payment_checkout.dart';

void main() {
  test('Checkout destinations are exact approved HTTPS hosts', () {
    expect(pulsePaymentCheckout('https://checkout.korapay.com/ref/pay'), isNotNull);
    expect(pulsePaymentCheckout('https://pay.squadco.com/ref'), isNotNull);
    for (final value in [
      'http://checkout.korapay.com/ref',
      'https://checkout.korapay.com.evil.test/ref',
      'https://evil.test@checkout.korapay.com/ref',
      'https://checkout.korapay.com:443/ref',
      'https://test-checkout.korapay.com/ref',
    ]) {
      expect(pulsePaymentCheckout(value), isNull, reason: value);
    }
    expect(pulsePaymentCheckout('https://test-checkout.korapay.com/ref', test: true), isNotNull);
    expect(pulsePaymentCheckout('https://checkout.korapay.com/ref', test: true), isNull);
  });
  test('Payment confirmation displays the returned exact currency quote', () {
    expect(pulseCheckoutPrice({'amount':150000,'currency':'NGN'}), '₦1500.00');
    expect(pulseCheckoutPrice({'amount':100,'currency':'USD'}), r'$1.00');
    expect(pulseCheckoutPrice({'amount':1.5,'currency':'NGN'}), isNull);
    expect(pulseCheckoutPrice({'amount':100,'currency':'XYZ'}), isNull);
  });
}
