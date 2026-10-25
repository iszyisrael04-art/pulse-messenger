import 'dart:async';
import 'package:country_picker/country_picker.dart';
import 'phone_rules.dart';
import 'brand.dart';
import 'appearance.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'validation.dart';
import 'privacy_policy.dart';
import 'profile_rules.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.allowRegistration = true});
  final bool allowRegistration;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final identity = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  Country country = Country.parse('NG');
  String? requestedPhone;
  int? signupAge;
  String get loginIdentity => method == 2
      ? (requestedPhone ??
            pulsePhoneNumber(identity.text, country.countryCode) ??
            '')
      : identity.text.trim();
  int method = 0; // email, Pulse username, phone
  bool register = false,
      busy = false,
      codeSent = false,
      reset = false,
      obscure = true;
  String? notice, privacyError;
  bool privacyAccepted = false;
  bool get needsAgreement => needsPrivacyAgreement(
    register: register,
    reset: reset,
    codeSent: codeSent,
  );
  Map<String, dynamic>? get signupData => register
      ? {
          'privacy_version': pulsePrivacyVersion,
          'privacy_accepted': true,
          'signup_age': signupAge,
        }
      : null;
  Timer? resendTimer;
  DateTime? resendAt;
  int get resendWait => resendAt == null
      ? 0
      : ((resendAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 60)
            .toInt();
  void codeRequested() {
    resendAt = DateTime.now().add(const Duration(seconds: 60));
    resendTimer?.cancel();
    resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {});
      if (resendWait == 0) t.cancel();
    });
  }

  Future<void> resend() async {
    if (busy || resendWait > 0 || !codeSent) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final id = loginIdentity;
      if (reset) {
        await db.auth.resetPasswordForEmail(id);
      } else if (method == 2) {
        await db.auth.signInWithOtp(
          phone: id,
          shouldCreateUser: register,
          data: signupData,
        );
      } else {
        await db.auth.resend(type: OtpType.signup, email: id);
      }
      if (mounted)
        setState(() {
          codeRequested();
          notice =
              'A new code was requested. Check your inbox/SMS and spam folder. Provider limits still apply.';
        });
    } on AuthException catch (e) {
      if (mounted)
        setState(
          () => notice = method == 2
              ? pulsePhoneError(e.code ?? '', e.message)
              : e.message,
        );
    } catch (_) {
      if (mounted)
        setState(
          () =>
              notice = 'Could not resend. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final db = Supabase.instance.client;
  @override
  void dispose() {
    resendTimer?.cancel();
    identity.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (needsAgreement && !privacyAccepted) {
      setState(
        () => privacyError =
            'Please read and agree to the Privacy Policy to create your account.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      final id = loginIdentity;
      final newPassword = password.text;
      if (codeSent) {
        await db.auth.verifyOTP(
          email: method == 2 ? null : id,
          phone: method == 2 ? id : null,
          token: code.text.trim(),
          type: method == 2
              ? OtpType.sms
              : reset
              ? OtpType.recovery
              : OtpType.signup,
        );
        if (reset)
          await db.auth.updateUser(UserAttributes(password: newPassword));
      } else if (reset) {
        await db.auth.resetPasswordForEmail(id);
        if (mounted)
          setState(() {
            codeRequested();
            codeSent = true;
            notice =
                'Enter the recovery code from your email and a new password.';
          });
      } else if (method == 2) {
        await db.auth.signInWithOtp(
          phone: id,
          shouldCreateUser: register,
          data: signupData,
        );
        if (mounted)
          setState(() {
            codeRequested();
            codeSent = true;
            requestedPhone = id;
            notice = 'Enter the SMS code sent to $id.';
          });
      } else if (method == 1) {
        final response = await db.functions.invoke(
          'pulse-login',
          body: {'username': id.toLowerCase(), 'password': password.text},
        );
        if (response.status != 200) throw Exception('Unable to sign in');
        final data = response.data as Map;
        await db.auth.setSession(data['refresh_token'] as String);
      } else if (register) {
        final response = await db.auth.signUp(
          email: id,
          password: password.text,
          data: signupData,
        );
        if (response.session == null && mounted)
          setState(() {
            codeRequested();
            codeSent = true;
            notice = 'Enter the confirmation code from your email.';
          });
      } else {
        await db.auth.signInWithPassword(email: id, password: password.text);
      }
    } on AuthException catch (e) {
      if (mounted)
        setState(
          () => notice = method == 2
              ? pulsePhoneError(e.code ?? '', e.message)
              : e.message,
        );
    } catch (_) {
      if (mounted)
        setState(
          () => notice =
              'Unable to continue. Check your details and connection, then try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: .12),
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.secondary.withValues(alpha: .08),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        PulseMark(size: 32),
                        SizedBox(width: 10),
                        PulseWordmark(size: 30),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      codeSent
                          ? 'Check your code'
                          : reset
                          ? 'Recover your account'
                          : register
                          ? 'Create your account'
                          : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      codeSent
                          ? 'Enter the verification code to continue.'
                          : reset
                          ? 'We’ll help you get back into Pulse.'
                          : 'Your conversations, videos and people — together.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (!codeSent && !reset)
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Email')),
                          ButtonSegment(value: 1, label: Text('Pulse')),
                          ButtonSegment(value: 2, label: Text('Phone')),
                        ],
                        selected: {method},
                        onSelectionChanged: busy
                            ? null
                            : (s) {
                                setState(() {
                                  method = s.first;
                                  register = false;
                                  privacyAccepted = false;
                                  privacyError = null;
                                  notice = null;
                                });
                              },
                      ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: identity,
                      autofillHints: [
                        method == 0
                            ? AutofillHints.email
                            : method == 2
                            ? AutofillHints.telephoneNumber
                            : AutofillHints.username,
                      ],
                      textInputAction: TextInputAction.next,
                      enabled: !busy && !codeSent,
                      keyboardType: method == 2
                          ? TextInputType.phone
                          : method == 0
                          ? TextInputType.emailAddress
                          : TextInputType.text,
                      decoration: InputDecoration(
                        prefixIcon: method == 2
                            ? TextButton(
                                onPressed: busy || codeSent
                                    ? null
                                    : () => showCountryPicker(
                                        context: context,
                                        showPhoneCode: true,
                                        favorite: const ['NG'],
                                        onSelect: (value) => setState(() {
                                          country = value;
                                          requestedPhone = null;
                                        }),
                                      ),
                                child: Text(
                                  '${country.countryCode} +${country.phoneCode}',
                                ),
                              )
                            : null,
                        labelText: method == 2
                            ? 'Phone number'
                            : method == 1
                            ? 'Pulse username'
                            : 'Email address',
                      ),
                      validator: (v) {
                        if (method == 1)
                          return validateUsername(v?.toLowerCase());
                        if (method == 2)
                          return pulsePhoneNumber(
                                    v ?? '',
                                    country.countryCode,
                                  ) !=
                                  null
                              ? null
                              : 'Enter a valid number for ${country.name}, or paste a full +country-code number.';
                        return RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(v ?? '')
                            ? null
                            : 'Enter a valid email address';
                      },
                    ),
                    if (method != 2 && (!codeSent || reset)) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        enabled: !busy,
                        autofillHints: [
                          register || reset
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        obscureText: obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: reset && codeSent
                              ? 'New password'
                              : 'Password',
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(() => obscure = !obscure);
                            },
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => reset && !codeSent
                            ? null
                            : (register || reset)
                            ? validatePassword(v)
                            : (v ?? '').isEmpty
                            ? 'Enter your password'
                            : null,
                      ),
                    ],
                    if (codeSent) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                        ),
                        validator: (v) => RegExp(r'^\d{6,8}$').hasMatch(v ?? '')
                            ? null
                            : 'Enter the code you received',
                      ),
                    ],
                    if (needsAgreement) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Your age',
                          helperText:
                              'Your age is private and is not shown on your profile.',
                        ),
                        onChanged: (v) => signupAge = int.tryParse(v.trim()),
                        validator: (v) {
                          final age = int.tryParse((v ?? '').trim());
                          return age == null || age < 1 || age > 120
                              ? 'Enter your age in years (1–120).'
                              : null;
                        },
                      ),
                    ],
                    if (needsAgreement)
                      PulsePrivacyAgreement(
                        accepted: privacyAccepted,
                        error: privacyError,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                privacyAccepted = v;
                                privacyError = null;
                              }),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: PulseLoader(size: 22),
                            )
                          : Text(
                              codeSent
                                  ? 'Verify and continue'
                                  : reset
                                  ? 'Send recovery code'
                                  : method == 2
                                  ? 'Send SMS code'
                                  : register
                                  ? 'Create account'
                                  : 'Sign in',
                            ),
                    ),
                    if ((method == 0 || method == 2) &&
                        !codeSent &&
                        !reset) ...[
                      if (widget.allowRegistration)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() {
                                    register = !register;
                                    privacyAccepted = false;
                                    privacyError = null;
                                    notice = null;
                                  });
                                },
                          child: Text(
                            register
                                ? 'Already have an account? Sign in'
                                : 'New to Pulse? Create an account',
                          ),
                        ),
                      if (method == 0)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() => reset = true);
                                },
                          child: const Text('Forgot password?'),
                        ),
                    ],
                    if (codeSent)
                      TextButton(
                        onPressed: busy || resendWait > 0 ? null : resend,
                        child: Text(
                          resendWait > 0
                              ? 'Resend code in ${resendWait}s'
                              : 'Resend verification code',
                        ),
                      ),
                    if (codeSent || reset)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                setState(() {
                                  codeSent = false;
                                  requestedPhone = null;
                                  reset = false;
                                  register = false;
                                  privacyAccepted = false;
                                  privacyError = null;
                                  notice = null;
                                  code.clear();
                                });
                              },
                        child: const Text('Back to sign in'),
                      ),
                    if (notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          notice!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Private beta • Messaging is not end-to-end encrypted yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
