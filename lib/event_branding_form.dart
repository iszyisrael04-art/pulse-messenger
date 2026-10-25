import 'dart:typed_data';
import 'package:flutter/material.dart';

class PulseBrandImage {
  const PulseBrandImage(this.bytes, this.extension, this.mime);
  final Uint8List bytes;
  final String extension, mime;
}

class PulseEventBrandingForm extends StatefulWidget {
  const PulseEventBrandingForm({
    super.key,
    required this.currentLogo,
    required this.chooseImage,
    required this.save,
    required this.restore,
    this.initialTitle = '',
  });
  final Widget currentLogo;
  final Future<PulseBrandImage?> Function() chooseImage;
  final Future<void> Function(PulseBrandImage image, String title, int days)
  save;
  final Future<void> Function() restore;
  final String initialTitle;
  @override
  State<PulseEventBrandingForm> createState() => _PulseEventBrandingFormState();
}

class _PulseEventBrandingFormState extends State<PulseEventBrandingForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  final days = TextEditingController(text: '7');
  PulseBrandImage? image;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    title.dispose();
    days.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final selected = await widget.chooseImage();
      if (mounted && selected != null) setState(() => image = selected);
    } catch (e) {
      if (mounted)
        setState(() => message = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit({bool restore = false}) async {
    if (busy) return;
    if (!restore) {
      if (!form.currentState!.validate()) return;
      if (image == null) {
        setState(() => message = 'Choose an event image first.');
        return;
      }
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (restore) {
        await widget.restore();
      } else {
        await widget.save(
          image!,
          title.text.trim(),
          int.parse(days.text.trim()),
        );
      }
      if (mounted)
        setState(() {
          message = restore
              ? 'Original Pulse logo restored.'
              : 'Event icon saved. Home and in-app splash updated.';
          if (restore) {
            image = null;
            title.clear();
          }
        });
    } catch (e) {
      if (mounted)
        setState(
          () => message =
              'Could not save the icon. ${e.toString().replaceFirst('Bad state: ', '')}',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Change Pulse icons')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: SizedBox.square(
              dimension: 112,
              child: image == null
                  ? widget.currentLogo
                  : Image.memory(
                      image!.bytes,
                      fit: BoxFit.contain,
                      key: const ValueKey('event-icon-preview'),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: busy ? null : pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              image == null ? 'Choose event image' : 'Choose another image',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: title,
            enabled: !busy,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Event name',
              hintText: 'Christmas or Eid Mubarak',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter an event name.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: days,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days until original logo returns',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 1 || n > 90
                  ? 'Choose 1 to 90 days.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'PNG, JPG or WebP, up to 2 MB. Changes the Home and in-app splash logos, plus the web favicon. The installed phone/desktop app icon requires an app update.',
          ),
          const SizedBox(height: 20),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                message!,
                key: const ValueKey('branding-message'),
                semanticsLabel: message,
              ),
            ),
          FilledButton.icon(
            onPressed: busy ? null : () => submit(),
            icon: const Icon(Icons.check),
            label: Text(busy ? 'Saving…' : 'Save event icon'),
          ),
          TextButton(
            onPressed: busy ? null : () => submit(restore: true),
            child: const Text('Restore original Pulse logo'),
          ),
        ],
      ),
    ),
  );
}
