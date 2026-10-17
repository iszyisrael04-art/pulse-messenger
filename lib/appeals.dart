import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'repository.dart' hide Row;

class PulseAppealPage extends StatefulWidget {
  const PulseAppealPage({super.key});
  @override
  State<PulseAppealPage> createState() => _PulseAppealPageState();
}

class _PulseAppealPageState extends State<PulseAppealPage> {
  final db = Supabase.instance.client;
  final message = TextEditingController();
  Map? challenge;
  File? file;
  String? name, notice, uploadedPath;
  bool busy = false, consent = false;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final c = await db.rpc('pulse_appeals', params: {'p_action': 'start'});
      if (mounted)
        setState(() {
          challenge = c as Map;
          file = null;
          uploadedPath = null;
          notice = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => notice =
              'Could not start an appeal. Sign in and check the server upgrade or try again later.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || file == null || !consent) return;
    setState(() => busy = true);
    try {
      if (await file!.length() > 26214400)
        throw const FormatException('Video must be 25 MB or smaller.');
      final id = challenge!['id'];
      final uid = db.auth.currentUser!.id;
      final ext = name!.split('.').last.toLowerCase();
      final path = '$uid/$id/appeal-video';
      if (uploadedPath == null)
        await db.storage
            .from('pulse-appeals')
            .upload(
              path,
              file!,
              fileOptions: FileOptions(
                contentType: ext == 'webm'
                    ? 'video/webm'
                    : ext == 'mov'
                    ? 'video/quicktime'
                    : 'video/mp4',
              ),
            );
      uploadedPath = path;
      await db.rpc(
        'pulse_appeals',
        params: {
          'p_action': 'submit',
          'p_data': {
            'id': id,
            'path': path,
            'message': message.text,
            'consent': consent,
          },
        },
      );
      if (mounted)
        setState(() {
          notice =
              'Appeal submitted for staff review. Email to Pulse support is queued; delivery depends on server mail setup.';
          challenge = null;
          file = null;
        });
    } on FormatException catch (e) {
      if (mounted) setState(() => notice = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => notice =
              'Could not submit. Check the video, connection and 15-minute challenge expiry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appeal account restriction')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Record a short video saying the exact phrase shown below. Staff review it manually. This is not an automatic identity or liveness check. You may record with your device camera, then select the video here.',
        ),
        const SizedBox(height: 16),
        if (challenge == null)
          FilledButton(
            onPressed: busy ? null : start,
            child: const Text('Get random phrase'),
          ),
        if (challenge != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                challenge!['phrase'],
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          Text('Expires: ${challenge!['expires_at']}'),
          TextButton(
            onPressed: busy ? null : start,
            child: const Text('Get a new phrase'),
          ),
          OutlinedButton.icon(
            onPressed: busy || uploadedPath != null
                ? null
                : () async {
                    final f = await FilePicker.pickFile(
                      type: FileType.custom,
                      allowedExtensions: ['mp4', 'webm', 'mov'],
                    );
                    if (f?.path != null && mounted)
                      setState(() {
                        file = File(f!.path!);
                        name = f.name;
                      });
                  },
            icon: const Icon(Icons.video_file_outlined),
            label: Text(name ?? 'Choose recorded appeal video'),
          ),
          TextField(
            controller: message,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Explain your appeal'),
          ),
          CheckboxListTile(
            value: consent,
            onChanged: busy ? null : (v) => setState(() => consent = v == true),
            title: const Text('Send this video and appeal to Pulse support'),
            subtitle: const Text(
              'Authorized staff can review it. A time-limited video link may be emailed to pulseservicemanagement@gmail.com. Do not include IDs or other sensitive documents.',
            ),
          ),
          FilledButton(
            onPressed: busy || file == null || !consent ? null : submit,
            child: Text(busy ? 'Submitting…' : 'Submit appeal'),
          ),
        ],
        if (notice != null) Text(notice!),
        const SizedBox(height: 16),
        const Text(
          '25 MB maximum. A video phrase is supporting evidence, not proof that an account belongs to you.',
        ),
      ],
    ),
  );
}

class PulseStaffAppeals extends StatefulWidget {
  const PulseStaffAppeals({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseStaffAppeals> createState() => _PulseStaffAppealsState();
}

class _PulseStaffAppealsState extends State<PulseStaffAppeals> {
  List rows = [];
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.repo.rpc('appeals', {'p_action': 'staff_list'});
      if (mounted) setState(() => rows = r as List);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Staff access or deployed server upgrade required.',
        );
    }
  }

  Future<void> review(Map a, String action) async {
    if (action == 'video') {
      try {
        final url = await widget.repo.db.storage
            .from('pulse-appeals')
            .createSignedUrl(a['video_path'], 300);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted)
          setState(() => error = 'Could not open private appeal video.');
      }
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$action appeal?'),
        content: Text(
          action == 'accept'
              ? 'Accepting restores account access.'
              : 'Rejecting keeps the current restriction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repo.rpc('appeals', {
        'p_action': action,
        'p_data': {'id': a['id']},
      });
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'Review action denied or failed.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Video appeals'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: ListView(
      children: [
        if (error != null) Text(error!),
        for (final a in rows)
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('@${a['username']}'),
                  subtitle: Text('${a['phrase']}\n${a['message']}'),
                ),
                Wrap(
                  children: [
                    for (final action in ['video', 'accept', 'reject'])
                      TextButton(
                        onPressed: () => review(a, action),
                        child: Text(action),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
