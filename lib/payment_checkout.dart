Uri? pulsePaymentCheckout(String value, {bool test = false}) {
  final url = Uri.tryParse(value);
  final hosts = test
      ? const {'sandbox-pay.squadco.com', 'test-checkout.korapay.com'}
      : const {'pay.squadco.com', 'checkout.korapay.com'};
  if (url == null || url.scheme != 'https' || !hosts.contains(url.host) ||
      url.userInfo.isNotEmpty || url.hasPort) return null;
  return url;
}

String? pulseCheckoutPrice(Map data) {
  final amount = data['amount'];
  final currency = data['currency'];
  if (amount is! num || !amount.isFinite || amount <= 0 || amount != amount.roundToDouble() ||
      !['NGN', 'USD'].contains(currency)) return null;
  return '${currency == 'NGN' ? '₦' : r'$'}${(amount / 100).toStringAsFixed(2)}';
}
