import 'dart:convert';

class PulsePremiumResult {
  PulsePremiumResult(this.expiresAt, this.alreadyRedeemed);
  final DateTime expiresAt;
  final bool alreadyRedeemed;
  factory PulsePremiumResult.parse(dynamic response) {
    final data = response is String ? jsonDecode(response) : response;
    if (data is! Map || data['expires_at'] is! String)
      throw const FormatException('Unconfirmed Premium response');
    final expiry = DateTime.tryParse(data['expires_at']);
    if (expiry == null)
      throw const FormatException('Unconfirmed Premium expiry');
    return PulsePremiumResult(expiry, data['already_redeemed'] == true);
  }
  String get date => expiresAt.toLocal().toIso8601String().substring(0, 10);
  String get message => alreadyRedeemed
      ? 'This code was already redeemed. Your Premium is active until $date.'
      : 'Premium activated until $date.';
}

String pulsePremiumError(String? code, String message) {
  final text = message.toLowerCase();
  if (text.contains('period has ended') ||
      text.contains('already redeemed') ||
      code == '23505')
    return 'This account has already used this one-time code.';
  if (text.contains('verify your email') || text.contains('verify your phone'))
    return 'Verify your email address or phone number first.';
  if (text.contains('code unavailable'))
    return 'This code is invalid, expired or no longer available.';
  if (code == 'PGRST202' || code == '42883' || code == '42P01')
    return 'The Premium service needs an update. Please try again later.';
  if (code == '42501' ||
      code == 'PGRST301' ||
      text.contains('sign in') ||
      text.contains('authentication'))
    return 'Please sign in again before redeeming a code.';
  if (text.contains('rate') || text.contains('too many'))
    return 'Too many attempts. Please wait before trying again.';
  return 'We could not confirm the code. Check your connection and retry; a retry will not grant Premium twice.';
}
