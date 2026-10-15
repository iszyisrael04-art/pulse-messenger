import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'avatar.dart';
import 'repository.dart' hide Row;

Future<String?> pickPulseContact(BuildContext context, PulseRepository repo) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ContactDialog(repo: repo),
    );

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.repo});
  final PulseRepository repo;
  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final query = TextEditingController();
  Timer? debounce;
  int generation = 0;
  Map<String, dynamic>? person;
  String? error;
  bool loading = false;
  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void search(String text) {
    debounce?.cancel();
    final own = ++generation;
    final value = text.trim().replaceFirst('@', '').toLowerCase();
    setState(() {
      person = null;
      error = null;
      loading = value.length >= 3;
    });
    if (value.length < 3) return;
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final p = await widget.repo.db
            .from('pulse_profiles')
            .select('id,username,display_name,avatar_path')
            .eq('username', value)
            .maybeSingle();
        if (mounted && own == generation)
          setState(() {
            person = p;
            error = p == null
                ? 'No account found with that username.'
                : p['id'] == widget.repo.uid
                ? 'That’s your own account.'
                : null;
          });
      } on PostgrestException catch (e) {
        if (mounted && own == generation) setState(() => error = e.message);
      } catch (_) {
        if (mounted && own == generation)
          setState(() => error = 'Could not search. Check your connection.');
      } finally {
        if (mounted && own == generation) setState(() => loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'New conversation',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Find someone by their exact Pulse username.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: query,
              autofocus: true,
              maxLength: 24,
              onChanged: search,
              decoration: InputDecoration(
                prefixText: '@',
                hintText: 'username',
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error!),
              ),
            if (person != null && error == null)
              Card(
                child: ListTile(
                  leading: PulseAvatar(
                    repo: widget.repo,
                    path: person!['avatar_path'],
                    name: person!['display_name'],
                  ),
                  title: Text(person!['display_name']),
                  subtitle: Text('@${person!['username']}'),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Your first message will appear as a request. They can reply after accepting.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: person == null || error != null || loading
                    ? null
                    : () => Navigator.pop(context, person!['username']),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Continue to chat'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
