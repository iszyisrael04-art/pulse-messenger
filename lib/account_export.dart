import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'data_export.dart';
import 'native_editor.dart';
import 'repository.dart';

class AccountExportPage extends StatefulWidget {
  const AccountExportPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<AccountExportPage> createState() => _AccountExportPageState();
}

class _AccountExportPageState extends State<AccountExportPage> {
  bool busy = false, cancel = false;
  String? status, error;
  @override
  void dispose() {
    cancel = true;
    super.dispose();
  }

  Future<void> export() async {
    if (busy) return;
    setState(() {
      busy = true;
      cancel = false;
      error = null;
      status = 'Preparing…';
    });
    File? output;
    try {
      final repo = widget.repo, owner = widget.repo.uid;
      bool stopped() =>
          cancel || !mounted || repo.db.auth.currentUser?.id != owner;
      String? folder;
      if (Platform.isWindows) {
        folder = await FilePicker.getDirectoryPath(
          dialogTitle: 'Save your Pulse data',
        );
        if (folder == null || stopped()) return;
      } else if (Platform.isAndroid) {
        folder = (await getTemporaryDirectory()).path;
      } else {
        throw UnsupportedError('Export supports Android and Windows.');
      }
      final name = 'Pulse-data-${const Uuid().v4()}.json';
      output = File('$folder/$name');
      final cutoff = DateTime.now().toUtc().toIso8601String();
      ExportSection section(
        String name,
        String table, {
        String? ownerColumn,
        String cursor = 'id',
        bool dated = true,
        required String fields,
      }) => ExportSection(name, (after, limit) async {
        if (stopped()) throw ExportCancelled();
        var query = repo.db.from(table).select(fields);
        if (ownerColumn != null) query = query.eq(ownerColumn, owner);
        if (dated) query = query.lte('created_at', cutoff);
        if (after != null) query = query.gt(cursor, after);
        final rows = await query
            .order(cursor)
            .limit(limit)
            .timeout(const Duration(seconds: 45));
        if (stopped()) throw ExportCancelled();
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }, cursor: cursor);
      await PulseDataExport().write(
        output,
        owner,
        [
          section(
            'profile',
            'pulse_profiles',
            ownerColumn: 'id',
            fields: 'id,username,display_name,bio,avatar_path,created_at',
          ),
          section(
            'conversations',
            'pulse_chats',
            fields: 'id,kind,name,owner_id,created_at',
          ),
          section(
            'accessible_messages',
            'pulse_messages',
            fields:
                'id,chat_id,sender_id,body,reply_to,attachment_path,created_at,edited_at,deleted_at,media_kind,media_mime,duration_ms,waveform',
          ),
          section(
            'my_statuses',
            'pulse_statuses',
            ownerColumn: 'user_id',
            fields:
                'id,user_id,body,created_at,expires_at,media_path,media_type',
          ),
          section(
            'my_posts_and_reels',
            'pulse_social_content',
            ownerColumn: 'author_id',
            fields:
                'id,author_id,kind,body,audience,state,media,created_at,edited_at',
          ),
          section(
            'my_comments',
            'pulse_social_comments',
            ownerColumn: 'author_id',
            fields: 'id,post_id,author_id,body,created_at,deleted_at',
          ),
          section(
            'message_requests',
            'pulse_chat_requests',
            cursor: 'chat_id',
            dated: false,
            fields: 'chat_id,sender_id,recipient_id,state,sent_at,updated_at',
          ),
        ],
        cancelled: stopped,
        progress: (section, rows) {
          if (mounted) setState(() => status = '$section · $rows records');
        },
      );
      if (stopped()) throw ExportCancelled();
      if (Platform.isAndroid) {
        await NativePulseEditor.saveDownload(output, name, 'application/json');
        await output.delete();
      }
      if (mounted)
        setState(
          () => status = Platform.isAndroid
              ? 'Saved to Downloads/Pulse/$name'
              : 'Saved to $folder/$name',
        );
    } on ExportCancelled {
      if (output != null && await output.exists()) await output.delete();
      if (mounted) setState(() => status = 'Export cancelled.');
    } catch (_) {
      if (output != null && await output.exists()) await output.delete();
      if (mounted)
        setState(
          () => error =
              'Export failed. Check your connection, storage permissions and available space. Android public downloads require Android 10 or newer.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Download your data')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.download_for_offline_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                'Your data, in your hands',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Export your profile, current conversations and accessible messages, your statuses, posts, Reels, comments and message requests as JSON. Photos and videos are referenced by storage path; their file bytes are not included. This is not a restorable backup or a complete legal data-access export.',
              ),
              const SizedBox(height: 12),
              const Text(
                'This file contains readable private messages. Keep it somewhere safe and remove it from shared devices. Export requires internet and reflects data available while it runs; it is not a transaction snapshot.',
              ),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SelectableText(status!),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton.icon(
                onPressed: busy ? null : export,
                icon: const Icon(Icons.download),
                label: const Text('Export my data'),
              ),
              if (busy)
                TextButton(
                  onPressed: () => setState(() {
                    cancel = true;
                    status = 'Cancelling…';
                  }),
                  child: const Text('Cancel export'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
