import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';
import 'validation.dart';

class ProfilePanel extends StatefulWidget {
  const ProfilePanel({super.key, required this.repo, required this.onSaved});
  final PulseRepository repo;
  final Future<void> Function() onSaved;
  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  final form = GlobalKey<FormState>();
  late TextEditingController name, username, bio;
  File? avatar;
  String? filename, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final p = widget.repo.me;
    name = TextEditingController(text: p?['display_name'] ?? '');
    username = TextEditingController(text: p?['username'] ?? '');
    bio = TextEditingController(text: p?['bio'] ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      var path = widget.repo.me?['avatar_path'] as String?;
      if (avatar != null)
        path = await widget.repo.upload(avatar!, filename!, avatar: true);
      await widget.repo.rpc('save_profile', {
        'p_username': username.text.trim().toLowerCase(),
        'p_name': name.text.trim(),
        'p_bio': bio.text,
        'p_avatar': path,
      });
      await widget.onSaved();
    } on PostgrestException catch (e) {
      if (mounted)
        setState(
          () => error = e.code == '23505'
              ? 'That username is already taken.'
              : e.message,
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Unable to save your profile. Check the image size and your connection.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Make Pulse yours',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Choose a unique username so people can find you.'),
              const SizedBox(height: 24),
              if (avatar != null)
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage: FileImage(avatar!),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final result = await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                        );
                        if (result != null && result.path != null)
                          setState(() {
                            avatar = File(result.path!);
                            filename = result.name;
                          });
                      },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  avatar == null
                      ? 'Choose profile picture'
                      : 'Change selected picture',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: username,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                ),
                validator: (v) => validateUsername(v?.trim().toLowerCase()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: bio,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'About you'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save profile'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
