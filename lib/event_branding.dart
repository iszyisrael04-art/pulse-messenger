import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'repository.dart' hide Row;
import 'dart:ui' as ui;
import 'event_branding_form.dart';

class PulseEventBranding extends ChangeNotifier {
  static final instance = PulseEventBranding();
  Timer? timer;
  String? path;
  String title = '';
  DateTime? until;
  String? get url =>
      path != null && until != null && until!.isAfter(DateTime.now())
      ? Supabase.instance.client.storage
            .from('pulse-branding')
            .getPublicUrl(path!)
      : null;
  void start() {
    if (timer != null) return;
    try {
      Supabase.instance.client;
    } catch (_) {
      return;
    }
    refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final r = await Supabase.instance.client
          .from('pulse_event_branding')
          .select('path,title,until_at')
          .eq('singleton', true)
          .single();
      path = r['path'] as String?;
      title = r['title']?.toString() ?? '';
      until = DateTime.tryParse(r['until_at']?.toString() ?? '');
      notifyListeners();
    } catch (_) {}
  }
}

class PulseEventLogo extends StatelessWidget {
  const PulseEventLogo({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final state = PulseEventBranding.instance;
    state.start();
    Widget fallback() => Image.asset(
      'assets/branding/pulse.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final url = state.url;
        return url == null
            ? fallback()
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => fallback(),
              );
      },
    );
  }
}

Future<void> editPulseEventBranding(
  BuildContext context,
  PulseRepository repo,
) async {
  await PulseEventBranding.instance.refresh();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PulseEventBrandingForm(
        currentLogo: const PulseEventLogo(size: 112),
        initialTitle: PulseEventBranding.instance.title,
        chooseImage: () async {
          final files = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          );
          if (files.isEmpty) return null;
          final path = files.first.path;
          if (path == null)
            throw StateError(
              'This image could not be opened. Choose a file saved on this device.',
            );
          final file = File(path);
          if (await file.length() > 2097152)
            throw StateError('Choose an image under 2 MB.');
          final bytes = await file.readAsBytes();
          try {
            final codec = await ui.instantiateImageCodec(
              bytes,
              targetWidth: 256,
            );
            final frame = await codec.getNextFrame();
            frame.image.dispose();
            codec.dispose();
          } catch (_) {
            throw StateError(
              'This image cannot be decoded. Choose a PNG, JPG or WebP image.',
            );
          }
          final ext = path.split('.').last.toLowerCase();
          if (!['png', 'jpg', 'jpeg', 'webp'].contains(ext))
            throw StateError('Choose a PNG, JPG or WebP image.');
          return PulseBrandImage(
            bytes,
            ext,
            ext == 'png'
                ? 'image/png'
                : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg',
          );
        },
        save: (image, title, days) async {
          final path = '${repo.uid}/${const Uuid().v4()}.${image.extension}';
          await repo.db.storage
              .from('pulse-branding')
              .uploadBinary(
                path,
                image.bytes,
                fileOptions: FileOptions(contentType: image.mime),
              );
          await repo.rpc('event_branding_save', {
            'p_path': path,
            'p_title': title,
            'p_days': days,
          });
          await PulseEventBranding.instance.refresh();
        },
        restore: () async {
          await repo.rpc('event_branding_save', {
            'p_path': null,
            'p_title': '',
            'p_days': 1,
          });
          await PulseEventBranding.instance.refresh();
        },
      ),
    ),
  );
}
