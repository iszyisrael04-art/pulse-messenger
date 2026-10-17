import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';
import 'premium_result.dart';

Future<PulsePremiumResult> redeemPulseCode(
  PulseRepository repo,
  String code,
) async {
  final normalized = code.trim().toUpperCase();
  if (normalized.isEmpty || normalized.length > 40)
    throw const FormatException('Enter a valid code.');
  final result = PulsePremiumResult.parse(
    await repo.rpc('redeem_result', {'p_code': normalized}),
  );
  repo.applyPremium(result.expiresAt);
  return result;
}

String redeemError(Object error) => error is PostgrestException
    ? pulsePremiumError(error.code, error.message)
    : error is FormatException && error.message == 'Enter a valid code.'
    ? error.message
    : pulsePremiumError(null, '');
