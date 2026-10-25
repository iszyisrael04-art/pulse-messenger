import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'repository.dart' hide Row;
import 'text_prompt.dart';

class PulseEventBranding extends ChangeNotifier {
  static final instance = PulseEventBranding();
  Timer? timer;
  String? path;
  DateTime? until;
  String? get url =>
      path != null && until != null && until!.isAfter(DateTime.now())
      ? Supabase.instance.client.storage
            .from('pulse-branding')
            .getPublicUrl(path!)
      : null;
  void start() {
    if (timer != null) return;
    refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final r = await Supabase.instance.client
          .from('pulse_event_branding')
          .select('path,until_at')
          .eq('singleton', true)
          .single();
      path = r['path'] as String?;
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
  final title = await showPulseTextPrompt(
    context,
    'Event title, e.g. Christmas or Eid Mubarak',
    maxLines: 1,
  );
  if (title == null || !context.mounted) return;
  final days = int.tryParse(
    await showPulseTextPrompt(
          context,
          'Days until original logo returns (1–90)',
          maxLines: 1,
        ) ??
        '',
  );
  if (days == null) return;
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  if (files.isEmpty || files.first.path == null) return;
  final file = File(files.first.path!);
  if (await file.length() > 2097152)
    throw StateError('Choose an image under 2 MB');
  final ext = file.path.split('.').last.toLowerCase();
  final path = '${repo.uid}/${const Uuid().v4()}.$ext';
  await repo.db.storage
      .from('pulse-branding')
      .upload(
        path,
        file,
        fileOptions: FileOptions(
          contentType: ext == 'png'
              ? 'image/png'
              : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg',
        ),
      );
  await repo.rpc('event_branding_save', {
    'p_path': path,
    'p_title': title,
    'p_days': days,
  });
  await PulseEventBranding.instance.refresh();
}
