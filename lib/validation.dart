String? validateUsername(String? value) =>
    RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(value ?? '')
    ? null
    : 'Use 3–24 lowercase letters, numbers or _. Start with a letter.';
String? validatePassword(String? value) =>
    (value ?? '').length >= 12 ? null : 'Use at least 12 characters.';

String? validatePasswordConfirmation(String password, String? confirmation) =>
    password == confirmation ? null : 'Passwords do not match.';
