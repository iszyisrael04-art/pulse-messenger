import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';
import 'validation.dart';
import 'avatar.dart';
import 'media.dart';
import 'social_premium.dart';
import 'social_repository.dart';

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

  Future<void> choosePicture({bool motion = false}) async {
    if (busy) return;
    if (motion && !widget.repo.premiumActive) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PulsePremiumPage(
            store: SocialStore(widget.repo),
            reason: 'Animated profile pictures are a Premium feature.',
          ),
        ),
      );
      return;
    }
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: motion ? ['gif'] : ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result?.path == null || !mounted) return;
    try {
      final selected = File(result!.path!);
      if (await selected.length() > 15728640)
        throw const FormatException(
          'Profile pictures must be 15 MB or smaller.',
        );
      if (motion) {
        final header = await selected.open();
        late List<int> bytes;
        try {
          bytes = await header.read(10);
        } finally {
          await header.close();
        }
        if (bytes.length < 10 ||
            ![
              'GIF87a',
              'GIF89a',
            ].contains(String.fromCharCodes(bytes.take(6)))) {
          throw const FormatException('Choose an animated GIF file.');
        }
        if ((bytes[6] | bytes[7] << 8) > 512 ||
            (bytes[8] | bytes[9] << 8) > 512) {
          throw const FormatException(
            'Use a GIF no larger than 512 × 512 pixels.',
          );
        }
      }
      if (mounted)
        setState(() {
          avatar = selected;
          filename = result.name;
          error = null;
        });
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not open that picture. Try another file.',
        );
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      var path = widget.repo.me?['avatar_path'] as String?;
      if (avatar != null)
        path = await widget.repo.upload(
          avatar!,
          filename!,
          avatar: true,
          contentType: mimeFor(filename!),
        );
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
          () => error =
              'Unable to save your profile. Check the image size and your connection.',
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
              Center(
                child: Tooltip(
                  message: 'Change profile picture',
                  child: InkWell(
                    onTap: busy ? null : () => choosePicture(),
                    customBorder: const CircleBorder(),
                    child: Stack(
                      children: [
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 104,
                            child: avatar == null
                                ? PulseAvatar(
                                    repo: widget.repo,
                                    path: widget.repo.me?['avatar_path'],
                                    name: name.text,
                                    radius: 52,
                                  )
                                : PulsePortrait(
                                    provider: ResizeImage(
                                      FileImage(avatar!),
                                      width: 256,
                                    ),
                                    animate:
                                        filename?.toLowerCase().endsWith(
                                              '.gif',
                                            ) ==
                                            true &&
                                        widget.repo.premiumActive,
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: Icon(
                              Icons.photo_camera_outlined,
                              size: 19,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : () => choosePicture(),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Change photo'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => choosePicture(motion: true),
                icon: const Icon(Icons.motion_photos_on_outlined),
                label: const Text('Animated picture · Premium'),
              ),
              const Text(
                'Photos: up to 15 MB. Premium GIFs: up to 512 × 512 pixels.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
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
