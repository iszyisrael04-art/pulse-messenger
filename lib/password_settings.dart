import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'validation.dart';

class PasswordSettingsPage extends StatefulWidget {
  const PasswordSettingsPage({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<PasswordSettingsPage> createState() => _PasswordSettingsPageState();
}

class _PasswordSettingsPageState extends State<PasswordSettingsPage> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController(),
      confirmation = TextEditingController(),
      nonce = TextEditingController();
  bool busy = false, obscure = true, needsCode = false;
  DateTime? sentAt;
  String? error, notice;
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    nonce.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (busy) return;
    if (sentAt != null && DateTime.now().difference(sentAt!).inSeconds < 60) {
      setState(
        () => error = 'Please wait one minute before requesting another code.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.auth.reauthenticate();
      if (mounted)
        setState(() {
          sentAt = DateTime.now();
          needsCode = true;
          notice = 'Check your verified email or phone for the security code.';
        });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not request a code. Check your connection.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.auth.updateUser(
        UserAttributes(
          password: password.text,
          nonce: nonce.text.trim().isEmpty ? null : nonce.text.trim(),
        ),
      );
      password.clear();
      confirmation.clear();
      nonce.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      if (mounted)
        setState(() {
          error = e.message;
          if (e.code == 'reauthentication_needed' ||
              e.code == 'reauthentication_not_valid')
            needsCode = true;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Password was not confirmed updated. Check your connection before retrying.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Change password')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Choose a unique password of at least 12 characters. Pulse does not add authentication credentials to diagnostics or exports.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: password,
                obscureText: obscure,
                enabled: !busy,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [AutofillHints.newPassword],
                validator: validatePassword,
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmation,
                obscureText: obscure,
                enabled: !busy,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (v) =>
                    validatePasswordConfirmation(password.text, v),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: busy ? null : sendCode,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Request a security code'),
              ),
              const Text(
                'Your authentication provider may require a security code. Email/SMS delivery must be configured.',
              ),
              if (needsCode)
                TextFormField(
                  controller: nonce,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(labelText: 'Security code'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Enter your security code'
                      : null,
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(notice!),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Please wait…' : 'Update password'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
