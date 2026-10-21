import 'package:phone_numbers_parser/phone_numbers_parser.dart';

String? pulsePhoneNumber(String input, String country) {
  if (input.trim().isEmpty) return null;
  try {
    final iso = IsoCode.values.where((v) => v.name == country).firstOrNull;
    final number = PhoneNumber.parse(input.trim(), callerCountry: iso);
    return number.isValid() ? number.international : null;
  } catch (_) {
    return null;
  }
}

String pulsePhoneError(String code, String message) {
  if (code == 'phone_provider_disabled' ||
      message.toLowerCase().contains('phone provider is disabled')) {
    return 'SMS sign-in is not enabled yet. Please use email or your Pulse username while Pulse finishes SMS setup.';
  }
  if (code == 'sms_send_failed' ||
      message.toLowerCase().contains('sms provider')) {
    return 'The SMS provider could not send a code. Check your number and try later, or use email.';
  }
  return message;
}
