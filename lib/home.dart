import 'gifter_ranks.dart';
import 'text_prompt.dart';
import 'chat_display.dart';
import 'message_selection.dart';
import 'channel_updates.dart';
import 'chat_composer.dart';
import 'chat_camera.dart';
import 'social_preview.dart';
import 'interest_picker.dart';
import 'contact_picker.dart';
import 'chat_state.dart';
import 'chat_tools.dart';
import 'account_export.dart';
import 'password_settings.dart';
import 'diagnostics.dart';
import 'brand.dart';
import 'appearance.dart';
import 'appearance_settings.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart' hide Row;
import 'profile.dart';
import 'privacy_policy.dart';
import 'support.dart';
import 'activity.dart';
import 'communities.dart';
import 'mailbox.dart';
import 'avatar.dart';
import 'admin.dart';
import 'channels.dart';
import 'notifications.dart';
import 'push.dart';
import 'presence_widgets.dart';
import 'statuses.dart';
import 'calls.dart';
import 'media.dart';
import 'voice.dart';
import 'social.dart';
import 'social_repository.dart';
import 'social_create.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.toggleTheme});
  final VoidCallback toggleTheme;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final PulseRepository repo;
  late final PulseChannelUpdates channelUpdates;
  int seenChannelSerial = 0;
  late final PulseCalls calls;
  bool openingCall = false, showingAnswer = false;
  bool interestPrompted = false;
  int section = 0, socialSection = 0;
  late final SocialStore social;
  final composer = TextEditingController(), search = TextEditingController();
  String? reply;
  String? selectedMessage, selectedChat;
  bool sending = false;
  int seenIncoming = 0, toastUnreadCount = 0;
  bool foreground = true;
  String chatFilter = 'all';
  String? toastChat, displayedChat, markingChat;
  OverlayEntry? messageToast;
  Timer? toastTimer;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo = PulseRepository(Supabase.instance.client)..addListener(changed);
    scroll.addListener(() {
      final chat = repo.activeChat;
      if (chat != null && viewingChat(chat)) scheduleRead(chat);
    });
    repo.isChatVisible = viewingChat;
    repo.initialize();
    channelUpdates = PulseChannelUpdates(repo)
      ..addListener(channelUpdatesChanged);
    channelUpdates.start();
    social = SocialStore(repo);
    social.activity.start();
    PulseNotifications.instance.setActivityTap(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseActivityPage(store: social)),
        );
      });
    });
    calls = PulseCalls(repo)..addListener(changed);
    calls.start();
    PulsePush.instance.onCall = () => calls.refresh();
    PulseNotifications.instance.setCallTap((value) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final action = value.startsWith('answer:')
            ? 'answer'
            : value.startsWith('decline:')
            ? 'decline'
            : '';
        final id = action.isEmpty ? value : value.substring(action.length + 1);
        await calls.refresh();
        if (!mounted) return;
        final call = calls.incoming;
        if (call == null || call['id'] != id) {
          notice('This call is no longer ringing.');
          return;
        }
        if (action == 'decline') {
          try {
            await calls.decline(id);
          } catch (e) {
            notice(callError(e));
          }
        } else if (action == 'answer') {
          await openCall(call);
        } else {
          await showIncomingAnswerScreen(call);
        }
      });
    });
  }

  void channelUpdatesChanged() {
    if (!mounted) return;
    setState(() {});
    final update = channelUpdates.latest;
    if (update == null || seenChannelSerial == channelUpdates.serial) return;
    seenChannelSerial = channelUpdates.serial;
    if (!PulseNotifications.instance.enabled ||
        !foreground ||
        channelUpdates.viewing(update['channel_id'] as String))
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !foreground ||
          (channelUpdates.counts[update['channel_id']] ?? 0) == 0)
        return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Row(
            children: [
              const Icon(Icons.campaign_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      update['name'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${channelUpdates.counts[update['channel_id']] ?? 1} unread · ${update['body']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelDetail(
                  repo: repo,
                  channelId: update['channel_id'],
                  updates: channelUpdates,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  bool viewingChat(String chat) =>
      mounted &&
      foreground &&
      socialSection == 3 &&
      section == 0 &&
      repo.activeChat == chat &&
      ModalRoute.of(context)?.isCurrent == true &&
      (!scroll.hasClients ||
          !scroll.position.hasContentDimensions ||
          scroll.position.maxScrollExtent - scroll.offset < 100);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) dismissToast();
    if (mounted) setState(() {});
  }

  void dismissToast() {
    toastTimer?.cancel();
    messageToast?.remove();
    messageToast = null;
    toastChat = null;
  }

  void scheduleRead(String chat) {
    final first = displayedChat != chat;
    displayedChat = chat;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          repo.activeChat != chat ||
          !foreground ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      if (first && scroll.hasClients)
        scroll.jumpTo(scroll.position.maxScrollExtent);
      if (!viewingChat(chat) || markingChat == chat) return;
      final unread =
          (repo.unread[chat] ?? 0) > 0 ||
          repo.messages.any(
            (m) =>
                m['sender_id'] != repo.uid &&
                m['deleted_at'] == null &&
                !repo.receipts.any(
                  (r) =>
                      r['message_id'] == m['id'] &&
                      r['user_id'] == repo.uid &&
                      r['read_at'] != null,
                ),
          );
      if (!unread || repo.error != null) return;
      markingChat = chat;
      try {
        await repo.markRead(chat);
      } catch (_) {
      } finally {
        markingChat = null;
      }
    });
  }

  Future<void> openProfile(String user) async {
    await PulseMedia.pauseAll();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Pulse profile')),
          body: SocialProfile(store: social, user: user),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> openChatStudio() async {
    final chat = repo.activeChat;
    if (chat == null) return;
    final text = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PulseChatTools(repo: repo, store: social, chat: chat),
      ),
    );
    if (!mounted) return;
    if (text != null && repo.activeChat == chat) {
      composer.text = text;
      composer.selection = TextSelection.collapsed(offset: text.length);
    }
    setState(() {});
  }

  void changed() {
    if (mounted) {
      if (!interestPrompted &&
          repo.me?['username'] != null &&
          !social.interestsChosen) {
        interestPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final chosen = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => PulseInterestPicker(store: social),
            ),
          );
          if (chosen == true && mounted) setState(() => socialSection = 0);
        });
      }
      if (selectedChat != repo.activeChat) {
        selectedChat = null;
        selectedMessage = null;
      }
      setState(() {});
      if (toastChat != null && (repo.unread[toastChat] ?? 0) < toastUnreadCount)
        dismissToast();
      if (repo.incomingSerial != seenIncoming && repo.incoming != null) {
        seenIncoming = repo.incomingSerial;
        showIncoming(repo.incoming!);
      }
    }
  }

  void showIncoming(Map<String, dynamic> message) {
    if (!PulseNotifications.instance.enabled ||
        !foreground ||
        viewingChat(message['chat_id']) ||
        (repo.unread[message['chat_id']] ?? 0) == 0)
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !foreground ||
          viewingChat(message['chat_id']) ||
          (repo.unread[message['chat_id']] ?? 0) == 0)
        return;
      toastChat = message['chat_id'];
      toastUnreadCount = repo.unread[toastChat] ?? 0;
      messageToast?.remove();
      toastTimer?.cancel();
      final sender = repo.profiles[message['sender_id']];
      final group = repo.chats
          .where(
            (chat) =>
                chat['id'] == message['chat_id'] && chat['kind'] == 'group',
          )
          .firstOrNull;
      final senderName = sender == null
          ? 'New message'
          : sender['display_name']?.toString() ?? 'New message';
      final notificationTitle = group == null
          ? senderName
          : '${group['name']} · $senderName';
      messageToast = OverlayEntry(
        builder: (c) => Positioned(
          top: MediaQuery.paddingOf(c).top + 12,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(c).colorScheme.surfaceContainerHigh,
                child: ListTile(
                  leading: PulseAvatar(
                    repo: repo,
                    path: sender?['avatar_path'],
                    name: sender?['display_name'] ?? 'Pulse',
                  ),
                  title: Text(
                    notificationTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${repo.unread[message['chat_id']] ?? 1} unread · ${message['body']?.toString().isNotEmpty == true ? message['body'] : 'Sent an attachment'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      messageToast?.remove();
                      messageToast = null;
                    },
                  ),
                  onTap: () async {
                    messageToast?.remove();
                    messageToast = null;
                    await repo.openChat(message['chat_id']);
                    if (mounted)
                      setState(() {
                        socialSection = 3;
                        section = 0;
                      });
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(messageToast!);
      toastTimer = Timer(const Duration(seconds: 5), () {
        messageToast?.remove();
        messageToast = null;
      });
    });
  }

  @override
  void dispose() {
    toastTimer?.cancel();
    messageToast?.remove();
    calls.removeListener(changed);
    PulsePush.instance.onCall = null;
    PulseNotifications.instance.setCallTap(null);
    calls.dispose();
    WidgetsBinding.instance.removeObserver(this);
    repo.removeListener(changed);
    PulseNotifications.instance.setActivityTap(null);
    social.activity.dispose();
    social.dispose();
    repo.dispose();
    channelUpdates.removeListener(channelUpdatesChanged);
    channelUpdates.dispose();
    composer.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      await repo.refresh();
    } on PostgrestException catch (e) {
      notice(e.message);
    } catch (_) {
      notice(
        'Unable to complete this action. Check your connection and try again.',
      );
    }
  }

  Future<String?> prompt(String title, {String initial = '', int lines = 1}) =>
      showPulseTextPrompt(
        context,
        title,
        initial: initial,
        minLines: 1,
        maxLines: lines,
        maxLength: 8000,
        allowEmpty: true,
        actionLabel: 'Continue',
      );

  Future<void> newChat({bool group = false}) async {
    final usernames = group
        ? await pickPulseMembers(context, repo)
        : await pickPulseContact(context, repo);
    if (usernames == null || usernames.isEmpty) return;
    String name = 'Pulse chat';
    if (group) {
      final n = await prompt('Group name');
      if (n == null || n.isEmpty) return;
      name = n;
    }
    await perform(() async {
      final names = usernames
          .split(',')
          .map((x) => x.trim().toLowerCase())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();
      final people = await repo.db
          .from('pulse_profiles')
          .select('id,username')
          .inFilter('username', names);
      if (people.length != names.length) {
        notice('One or more usernames could not be found.');
        return;
      }
      final id = await repo.rpc('start_chat', {
        'p_users': people.map((p) => p['id']).toList(),
        'p_name': name,
        'p_group': group,
      });
      await repo.refresh();
      await repo.openChat(id as String);
      if (mounted)
        setState(() {
          section = 0;
          socialSection = 3;
        });
    });
  }

  Future<void> captureChat(bool note) async {
    if (sending || !repo.canReply(repo.activeChat)) return;
    final chat = repo.activeChat, owner = repo.uid, replying = reply;
    if (chat == null) return;
    final caption = composer.text;
    setState(() => sending = true);
    PulseCapture? capture;
    PulseStudioResult? edited;
    try {
      await PulseMedia.pauseAll();
      if (!mounted) return;
      capture = await Navigator.push<PulseCapture>(
        context,
        MaterialPageRoute(builder: (_) => PulseCameraPage(note: note)),
      );
      if (capture == null || !mounted) return;
      var file = capture.file;
      var text = caption;
      if (!note) {
        edited = await Navigator.push<PulseStudioResult>(
          context,
          MaterialPageRoute(
            builder: (_) => SocialSelectionPreview(
              file: file,
              video: capture!.video,
              caption: caption,
            ),
          ),
        );
        if (edited == null || !mounted) return;
        file = edited.file;
        text = edited.caption ?? caption;
      }
      if (repo.uid != owner || !repo.canReply(chat))
        throw StateError('Chat unavailable');
      final mime = capture.video ? 'video/mp4' : mimeFor(file.path);
      final attachment = await repo.upload(
        file,
        note ? 'pulse_note.mp4' : file.uri.pathSegments.last,
        chatId: chat,
        contentType: mime,
      );
      await repo.send(
        text,
        reply: replying,
        attachment: attachment,
        chatId: chat,
        mediaKind: capture.video ? 'video' : 'image',
        mediaMime: mime,
        duration: capture.video ? capture.duration : null,
      );
      if (repo.activeChat == chat && composer.text == caption) {
        composer.clear();
        if (reply == replying) reply = null;
      }
    } catch (_) {
      notice(
        'Capture could not be sent. Check the connection; chat files must be under 10 MB.',
      );
    } finally {
      for (final file in {capture?.file, edited?.file}.whereType<File>()) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> send({bool file = false}) async {
    if (sending || !repo.canReply(repo.activeChat)) return;
    if (!file && composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      String? attachment, mime;
      final chatId = repo.activeChat;
      final replying = reply;
      var body = composer.text;
      if (file) {
        final result = await FilePicker.pickFile();
        if (result == null) return;
        final selected = result;
        if (selected.path == null) throw Exception('File unavailable');
        mime = mimeFor(selected.name);
        var uploadFile = File(selected.path!);
        PulseStudioResult? edited;
        if (['image', 'video'].contains(kindFor(mime))) {
          edited = await Navigator.push<PulseStudioResult>(
            context,
            MaterialPageRoute(
              builder: (_) => SocialSelectionPreview(
                file: uploadFile,
                video: kindFor(mime!) == 'video',
                caption: body,
              ),
            ),
          );
          if (edited == null) return;
          uploadFile = edited.file;
          body = edited.caption ?? body;
          mime = mimeFor(uploadFile.path);
        }
        try {
          attachment = await repo.upload(
            uploadFile,
            uploadFile.uri.pathSegments.last,
            contentType: mime,
            chatId: chatId,
          );
        } finally {
          if (edited != null && uploadFile.path != selected.path) {
            try {
              await uploadFile.delete();
            } catch (_) {}
          }
        }
        if (body.trim().isEmpty && kindFor(mime!) == 'file')
          body = selected.name;
      }
      await repo.send(
        body,
        reply: replying,
        attachment: attachment,
        chatId: chatId,
        mediaKind: mime == null ? null : kindFor(mime),
        mediaMime: mime,
      );
      composer.clear();
      reply = null;
      if (scroll.hasClients)
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
    } catch (_) {
      notice(
        'Could not send. Files require a connection and must be under 10 MB.',
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> recordVoice() async {
    final chatId = repo.activeChat;
    if (sending || chatId == null) return;
    final replying = reply;
    await PulseMedia.pauseAll();
    if (!mounted) return;
    final note = await showDialog<PulseVoiceNote>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceRecorderDialog(),
    );
    if (note == null) return;
    try {
      if (!mounted) return;
      setState(() => sending = true);
      final path = await repo.upload(
        note.file,
        'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        chatId: chatId,
      );
      await repo.send(
        '',
        reply: replying,
        attachment: path,
        chatId: chatId,
        mediaKind: 'audio',
        mediaMime: 'audio/mp4',
        duration: note.durationMs,
        waveform: note.waveform,
      );
      reply = null;
    } catch (_) {
      notice(
        'Could not upload voice note. Check your connection and try again.',
      );
    } finally {
      try {
        if (await note.file.exists()) await note.file.delete();
      } catch (_) {}
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> startCall(String kind) async {
    if (openingCall || repo.activeChat == null) return;
    await PulseMedia.pauseAll();
    openingCall = true;
    try {
      final credentials = await calls.invoke(
        'start',
        chatId: repo.activeChat,
        kind: kind,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PulseCallScreen(calls: calls, credentials: credentials),
        ),
      );
    } catch (error) {
      notice(callError(error));
    } finally {
      openingCall = false;
      await calls.refresh();
    }
  }

  Future<void> openCall(Map<String, dynamic> call) async {
    if (openingCall) return;
    await PulseMedia.pauseAll();
    openingCall = true;
    try {
      await calls.incomingTone.play(null);
      await PulseNotifications.instance.clearCall(call['id']);
      final action = calls.ownMember(call)?['state'] == 'ringing'
          ? 'accept'
          : 'join';
      final credentials = await calls.invoke(action, callId: call['id']);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PulseCallScreen(calls: calls, credentials: credentials),
        ),
      );
    } catch (error) {
      notice(callError(error));
    } finally {
      openingCall = false;
      await calls.refresh();
    }
  }

  Future<void> showIncomingAnswerScreen(Map<String, dynamic> call) async {
    if (openingCall || showingAnswer || !mounted) return;
    showingAnswer = true;
    final answer = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (c) => AnimatedBuilder(
          animation: calls,
          builder: (_, __) {
            final current = calls.incoming;
            final ringing = current != null && current['id'] == call['id'];
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_circle_rounded, size: 112),
                        const SizedBox(height: 24),
                        Text(
                          repo.profiles[call['caller_id']]?['display_name'] ??
                              'Pulse caller',
                          style: Theme.of(c).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ringing
                              ? 'Incoming ${call['kind']} call'
                              : 'Call ended',
                        ),
                        const SizedBox(height: 64),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () => Navigator.pop(c, false),
                              icon: const Icon(Icons.call_end),
                              label: Text(ringing ? 'Decline' : 'Close'),
                            ),
                            if (ringing)
                              FilledButton.icon(
                                onPressed: () => Navigator.pop(c, true),
                                icon: const Icon(Icons.call),
                                label: const Text('Answer'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    showingAnswer = false;
    if (!mounted) return;
    if (answer == true) {
      await calls.refresh();
      if (mounted && calls.incoming?['id'] == call['id']) await openCall(call);
    } else if (answer == false && calls.incoming?['id'] == call['id']) {
      try {
        await calls.decline(call['id']);
      } catch (e) {
        notice(callError(e));
      }
    }
  }

  Widget incomingCallBanner(Map<String, dynamic> call) => MaterialBanner(
    content: Text(
      '${repo.profiles[call['caller_id']]?['display_name'] ?? 'Someone'} is calling · ${call['kind']}',
    ),
    leading: const Icon(Icons.ring_volume),
    actions: [
      TextButton(
        onPressed: () async {
          try {
            await calls.decline(call['id']);
          } catch (e) {
            notice(callError(e));
          }
        },
        child: const Text('Decline'),
      ),
      FilledButton(
        onPressed: () => openCall(call),
        child: const Text('Accept'),
      ),
    ],
  );

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    if (message['pending'] == true) {
      await messageAction(message, 'discard');
      return;
    }
    final mine = message['sender_id'] == repo.uid;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Choose who this message is removed for.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'hide'),
            child: const Text('Delete for me'),
          ),
          if (mine && message['deleted_at'] == null)
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'delete'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice != null) await messageAction(message, choice);
  }

  void clearMessageSelection() {
    setState(() {
      selectedMessage = null;
      selectedChat = null;
    });
  }

  Future<void> messageAction(Map<String, dynamic> m, String action) async {
    final mine = m['sender_id'] == repo.uid;
    if (action == 'copy') {
      final text = m['body'] as String? ?? '';
      if (m['deleted_at'] != null || text.trim().isEmpty) return;
      try {
        await Clipboard.setData(ClipboardData(text: text));
        notice('Copied');
      } catch (_) {
        notice('Could not copy this message. Please try again.');
      }
      return;
    }
    if (action == 'reply') {
      setState(() => reply = m['id']);
      return;
    }
    if (action == 'discard') {
      await repo.discardPending(m['id']);
      return;
    }
    await perform(() async {
      if (action == 'delete' && mine)
        await repo.rpc('change_message', {
          'p_id': m['id'],
          'p_body': '',
          'p_delete': true,
        });
      if (action == 'edit' && mine) {
        final value = await prompt(
          'Edit message',
          initial: m['body'],
          lines: 3,
        );
        if (value != null && value.isNotEmpty)
          await repo.rpc('change_message', {
            'p_id': m['id'],
            'p_body': value,
            'p_delete': false,
          });
      }
      if (action == 'hide' || action == 'star') {
        final prefs = repo.preferences.where((p) => p['message_id'] == m['id']);
        final starred = prefs.isNotEmpty && prefs.first['starred'] == true;
        await repo.rpc('message_pref', {
          'p_id': m['id'],
          'p_hidden': action == 'hide',
          'p_starred': action == 'star' ? !starred : starred,
        });
      }
      if (action.startsWith('react:'))
        await repo.rpc('react', {
          'p_id': m['id'],
          'p_emoji': action.substring(6),
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final firstSetup = repo.me != null && repo.me!['username'] == null;
    final titles = [
      'Home',
      'Reels',
      'Create',
      'Chats',
      'Communities',
      'Profile',
    ];
    final icons = [
      Icons.home_outlined,
      Icons.play_circle_outline,
      Icons.add_box_outlined,
      Icons.chat_bubble_outline,
      Icons.groups_outlined,
      Icons.account_circle_outlined,
    ];
    final messenger = section == 0
        ? chatsView(wide)
        : section == 1
        ? CallsList(calls: calls, open: openCall)
        : section == 2
        ? updatesView()
        : ChannelsScreen(repo: repo, updates: channelUpdates);
    final body = repo.me == null
        ? Center(
            child: repo.error == null
                ? const PulseLoader()
                : TextButton(
                    onPressed: repo.refresh,
                    child: const Text('Reconnect to load your account'),
                  ),
          )
        : firstSetup
        ? ProfilePanel(repo: repo, onSaved: repo.refresh)
        : socialSection == 0
        ? SocialFeed(
            key: ValueKey('home-${social.interests.join(",")}'),
            store: social,
            mode: 'for_you',
          )
        : socialSection == 1
        ? PulseReels(store: social)
        : socialSection == 3
        ? Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Semantics(
                        selected: section == i,
                        child: IconButton(
                          tooltip: const [
                            'Chats',
                            'Calls',
                            'Updates',
                            'Channels',
                          ][i],
                          isSelected: section == i,
                          onPressed: () => setState(() => section = i),
                          icon: Badge(
                            isLabelVisible: i == 3 && channelUpdates.total > 0,
                            label: Text(
                              channelUpdates.total > 99
                                  ? '99+'
                                  : '${channelUpdates.total}',
                            ),
                            child: Icon(
                              const [
                                Icons.chat_bubble_outline,
                                Icons.call_outlined,
                                Icons.donut_large_outlined,
                                Icons.campaign_outlined,
                              ][i],
                            ),
                          ),
                          selectedIcon: Badge(
                            isLabelVisible: i == 3 && channelUpdates.total > 0,
                            label: Text(
                              channelUpdates.total > 99
                                  ? '99+'
                                  : '${channelUpdates.total}',
                            ),
                            child: Icon(
                              const [
                                Icons.chat_bubble,
                                Icons.call,
                                Icons.donut_large,
                                Icons.campaign,
                              ][i],
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Pulse mail & requests',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PulseMailbox(repo: repo),
                      ),
                    ),
                    icon: const Icon(Icons.mail_outline),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: openSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              Expanded(child: messenger),
            ],
          )
        : socialSection == 4
        ? groupsView()
        : SocialProfile(store: social, user: repo.uid, settings: openSettings);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: socialSection,
                onDestinationSelected: (v) {
                  selectSocial(v);
                },
                extended: MediaQuery.sizeOf(context).width >= 1100,
                labelType: NavigationRailLabelType.none,
                groupAlignment: -.8,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: PulseMark(size: 40, tile: true),
                ),
                destinations: List.generate(
                  6,
                  (i) => NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(titles[i]),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (repo.error != null)
                    MaterialBanner(
                      content: Text(repo.error!),
                      leading: const Icon(Icons.cloud_off),
                      actions: [
                        TextButton(
                          onPressed: repo.refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  if (calls.incoming != null)
                    incomingCallBanner(calls.incoming!),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : PulseBottomNav(
              selected: socialSection,
              onSelect: selectSocial,
              unread: repo.unread.values.fold(0, (a, b) => a + b),
              profileImage: PulseAvatar(
                repo: repo,
                path: repo.me?['avatar_path'],
                name: repo.me?['display_name'] ?? 'Your',
                radius: 13,
              ),
            ),
    );
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('PULSE settings')),
          body: settingsView(),
        ),
      ),
    );
  }

  Future<void> selectSocial(int value) async {
    await PulseMedia.pauseAll();
    if (!mounted) return;
    if (repo.me == null || repo.me!['username'] == null) return;
    if (value == 2) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => SocialComposer(store: social)),
      );
      if (saved == true && mounted) setState(() => socialSection = 5);
      return;
    }
    setState(() => socialSection = value);
  }

  Widget header(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
        ),
        if (action != null) action,
      ],
    ),
  );
  Widget chatsView(bool wide) {
    final visibleChats = repo.chats.where((c) {
      if (!'${repo.chatName(c)} ${pulseChatPreview(repo.chatSummaries[c['id']], repo.uid)}'
          .toLowerCase()
          .contains(search.text.toLowerCase()))
        return false;
      final request = repo.requestFor(c['id']);
      return switch (chatFilter) {
        'friends' =>
          c['kind'] == 'direct' &&
              (request == null || request['state'] == 'accepted'),
        'groups' => c['kind'] == 'group',
        'unread' => (repo.unread[c['id']] ?? 0) > 0,
        'requests' => request?['state'] == 'pending',
        _ => true,
      };
    }).toList();
    visibleChats.sort((a, b) {
      final at = DateTime.tryParse(
            repo.chatSummaries[a['id']]?['created_at'] ?? a['created_at'] ?? '',
          ),
          bt = DateTime.tryParse(
            repo.chatSummaries[b['id']]?['created_at'] ?? b['created_at'] ?? '',
          );
      return (bt ?? DateTime(1970)).compareTo(at ?? DateTime(1970));
    });
    final list = Column(
      children: [
        header(
          'Chats',
          action: IconButton(
            tooltip: 'New conversation',
            onPressed: () => newChat(),
            icon: const Icon(Icons.edit_square),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: search,
            onChanged: (_) {
              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final e in {
                  'all': 'All',
                  'friends': 'Friends',
                  'unread': 'Unread',
                  'groups': 'Groups',
                  'requests': 'Requests',
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: chatFilter == e.key,
                    onSelected: (_) => setState(() => chatFilter = e.key),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: visibleChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.forum_outlined, size: 60),
                      const SizedBox(height: 16),
                      Text(
                        chatFilter == 'unread'
                            ? 'You’re all caught up'
                            : chatFilter == 'requests'
                            ? 'No pending requests'
                            : 'No conversations found',
                      ),
                      TextButton(
                        onPressed: () => newChat(),
                        child: const Text('Find someone by username'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: visibleChats.map((c) {
                    final member = (c['pulse_members'] as List).where(
                      (m) => m['user_id'] != repo.uid,
                    );
                    final person = member.isEmpty
                        ? null
                        : repo.profiles[member.first['user_id']];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        minLeadingWidth: 58,
                        horizontalTitleGap: 14,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        selected: repo.activeChat == c['id'],
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        leading: GestureDetector(
                          onTap: person == null || c['kind'] == 'group'
                              ? null
                              : () => openProfile(person['id']),
                          child: PulseAvatar(
                            repo: repo,
                            path: c['kind'] == 'group'
                                ? (repo.chatSummaries[c['id']]?['avatar_path'])
                                : (person?['avatar_path']),
                            userId: c['kind'] == 'group' ? null : person?['id'],
                            name: repo.chatName(c),
                            radius: 29,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              pulseChatTime(
                                DateTime.tryParse(
                                  repo.chatSummaries[c['id']]?['created_at'] ??
                                      '',
                                ),
                                DateTime.now(),
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: (repo.unread[c['id']] ?? 0) > 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if ((repo.unread[c['id']] ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Badge(
                                  label: Text(
                                    (repo.unread[c['id']] ?? 0) > 99
                                        ? '99+'
                                        : '${repo.unread[c['id']]}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          repo.chatName(c),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          pulseChatPreview(
                            repo.chatSummaries[c['id']],
                            repo.uid,
                            senderName:
                                repo.profiles[repo
                                    .chatSummaries[c['id']]?['sender_id']]?['display_name'] ??
                                'Pulse user',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            height: 1.6,
                            fontSize: 13,
                            fontWeight: (repo.unread[c['id']] ?? 0) > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          repo.openChat(c['id']);
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
    if (!wide && repo.activeChat != null) return chatView(mobile: true);
    if (!wide) return list;
    return Row(
      children: [
        SizedBox(width: 320, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: repo.activeChat == null
              ? const FeatureNotice(
                  icon: Icons.hub_outlined,
                  title: 'Stay in your circle',
                  text:
                      'Choose a conversation or start a new one with a Pulse username.',
                )
              : chatView(),
        ),
      ],
    );
  }

  Widget chatView({bool mobile = false}) {
    final matches = repo.chats.where((c) => c['id'] == repo.activeChat);
    final chat = matches.isEmpty ? null : matches.first;
    final name = chat == null ? 'Conversation' : repo.chatName(chat);
    final selected = selectedChat == repo.activeChat
        ? repo.visibleMessages
              .where((m) => m['id'] == selectedMessage)
              .firstOrNull
        : null;
    final peer = (chat?['pulse_members'] as List? ?? [])
        .where((m) => m['user_id'] != repo.uid)
        .firstOrNull;
    if (repo.activeChat != null) scheduleRead(repo.activeChat!);
    final filtered = repo.visibleMessages
        .where(
          (m) => m['body'].toString().toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        if (selected != null)
          PulseMessageSelection(
            canCopy:
                selected['deleted_at'] == null &&
                (selected['body'] as String? ?? '').trim().isNotEmpty,
            canReact:
                selected['pending'] != true && selected['deleted_at'] == null,
            onClose: clearMessageSelection,
            onAction: (action) {
              clearMessageSelection();
              unawaited(messageAction(selected, action));
            },
            onDelete: () {
              clearMessageSelection();
              unawaited(deleteMessage(selected));
            },
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
            child: Row(
              children: [
                if (mobile)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        repo.activeChat = null;
                        reply = null;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: peer == null || chat?['kind'] == 'group'
                        ? null
                        : () => openProfile(peer['user_id']),
                    child: PulseAvatar(
                      repo: repo,
                      path: (chat?['kind'] == 'group')
                          ? (repo.chatSummaries[repo
                                .activeChat]?['avatar_path'])
                          : (repo.profiles[peer?['user_id']]?['avatar_path']),
                      name: name,
                      userId: chat?['kind'] == 'group'
                          ? null
                          : peer?['user_id'],
                      radius: 21,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: peer == null || chat?['kind'] == 'group'
                            ? null
                            : () => openProfile(peer['user_id']),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (chat?['kind'] != 'group' && peer != null)
                        PulsePresenceLabel(
                          presence: repo.presence,
                          userId: peer['user_id'],
                        ),
                      Text(
                        chat?['kind'] == 'group'
                            ? '${(chat?['pulse_members'] as List? ?? []).length} members'
                            : '${repo.requestFor(repo.activeChat)?['state'] == 'pending' ? 'Message request' : 'Friend chat'}${peer == null ? '' : ' · @${repo.profiles[peer['user_id']]?['username'] ?? 'pulse'}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chat studio: private notes, replies and styles',
                  onPressed: openChatStudio,
                  icon: const Icon(Icons.edit_note_rounded),
                ),
                if (chat?['kind'] == 'group')
                  IconButton(
                    tooltip: 'Manage group member',
                    icon: const Icon(Icons.manage_accounts),
                    onPressed: () async {
                      final username = await pickPulseContact(context, repo);
                      if (username == null || username.isEmpty) return;
                      if (!mounted) return;
                      final operation = await showDialog<String>(
                        context: context,
                        builder: (c) => SimpleDialog(
                          title: const Text('Group member action'),
                          children: ['add', 'remove', 'admin', 'member']
                              .map(
                                (a) => SimpleDialogOption(
                                  onPressed: () => Navigator.pop(c, a),
                                  child: Text(a),
                                ),
                              )
                              .toList(),
                        ),
                      );
                      if (operation == null) return;
                      await perform(() async {
                        final p = await repo.db
                            .from('pulse_profiles')
                            .select('id')
                            .eq('username', username.toLowerCase())
                            .single();
                        await repo.rpc('manage_group', {
                          'p_chat': repo.activeChat,
                          'p_user': p['id'],
                          'p_action': operation,
                        });
                      });
                    },
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'voice' || v == 'video') {
                      await startCall(v);
                      return;
                    }
                    if (v == 'refresh') {
                      await perform(() async {
                        await repo.refresh();
                        await repo.markRead();
                      });
                      return;
                    }
                    if (v == 'profile' && peer != null) {
                      await openProfile(peer['user_id']);
                      return;
                    }
                    if (chat == null) return;
                    final members = (chat['pulse_members'] as List).where(
                      (m) => m['user_id'] != repo.uid,
                    );
                    if (members.isEmpty) return;
                    final user = members.first['user_id'];
                    if (v == 'block')
                      await perform(() async {
                        await repo.rpc('block_user', {
                          'p_user': user,
                          'p_block': true,
                        });
                      });
                    if (v == 'report') {
                      final reason = await prompt(
                        'Report this account',
                        lines: 3,
                      );
                      if (reason != null && reason.isNotEmpty)
                        await perform(() async {
                          await repo.rpc('report_user', {
                            'p_user': user,
                            'p_reason': reason,
                          });
                        });
                    }
                  },
                  itemBuilder: (_) => [
                    if (chat?['kind'] == 'direct' && peer != null)
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('View profile'),
                      ),
                    PopupMenuItem(
                      value: 'voice',
                      enabled:
                          repo.requestFor(repo.activeChat) == null ||
                          repo.requestFor(repo.activeChat)?['state'] ==
                              'accepted',
                      child: const Text('Voice call'),
                    ),
                    PopupMenuItem(
                      value: 'video',
                      enabled:
                          repo.requestFor(repo.activeChat) == null ||
                          repo.requestFor(repo.activeChat)?['state'] ==
                              'accepted',
                      child: const Text('Video call'),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh / mark read'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'block',
                      child: Text('Block contact'),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report contact'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: PulseWallpaper(
            child: repo.busy && filtered.isEmpty
                ? const Center(child: PulseLoader())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (c, i) {
                      final time = DateTime.tryParse(
                        filtered[i]['created_at'] ?? '',
                      )?.toLocal();
                      final previous = i == 0
                          ? null
                          : DateTime.tryParse(
                              filtered[i - 1]['created_at'] ?? '',
                            )?.toLocal();
                      final newDay =
                          time != null &&
                          (previous == null ||
                              previous.year != time.year ||
                              previous.month != time.month ||
                              previous.day != time.day);
                      return Column(
                        children: [
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Chip(
                                label: Text(
                                  pulseChatDay(time!, DateTime.now()),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPress: () => setState(() {
                              selectedChat = repo.activeChat;
                              selectedMessage = filtered[i]['id'];
                            }),
                            onSecondaryTap: () => setState(() {
                              selectedChat = repo.activeChat;
                              selectedMessage = filtered[i]['id'];
                            }),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: selected?['id'] == filtered[i]['id']
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: .10)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: messageBubble(filtered[i]),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        if (repo.requestFor(repo.activeChat) != null &&
            repo.requestFor(repo.activeChat)!['state'] != 'accepted')
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: ListTile(
              title: Text(
                repo.requestFor(repo.activeChat)!['state'] == 'declined'
                    ? 'Message request declined'
                    : repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid
                    ? 'Message request'
                    : 'Waiting for acceptance',
              ),
              subtitle: Text(
                repo.requestFor(repo.activeChat)!['state'] == 'declined'
                    ? 'Messaging is unavailable for this request.'
                    : repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid
                    ? 'Accept before replying. You can also decline or block.'
                    : 'You can send messages; they can reply after accepting.',
              ),
              trailing:
                  repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid &&
                      repo.requestFor(repo.activeChat)!['state'] == 'pending'
                  ? Wrap(
                      children: [
                        TextButton(
                          onPressed: () => perform(
                            () => repo.rpc('respond_request', {
                              'p_chat': repo.activeChat,
                              'p_accept': false,
                            }),
                          ),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: () => perform(
                            () => repo.rpc('respond_request', {
                              'p_chat': repo.activeChat,
                              'p_accept': true,
                            }),
                          ),
                          child: const Text('Accept'),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        if (reply != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.reply),
            title: const Text('Replying to a message'),
            trailing: IconButton(
              onPressed: () {
                setState(() => reply = null);
              },
              icon: const Icon(Icons.close),
            ),
          ),
        PulseChatComposer(
          controller: composer,
          enabled: repo.canReply(repo.activeChat),
          busy: sending,
          onSend: () => send(),
          onAttach: () => send(file: true),
          onVoice: recordVoice,
          onCamera: (note) => captureChat(note),
        ),
      ],
    );
  }

  Widget chatMessageMenu(Map<String, dynamic> m) {
    final pending = m['pending'] == true,
        deleted = m['deleted_at'] != null,
        mine = m['sender_id'] == repo.uid;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 16,
      onSelected: (v) => messageAction(m, v),
      itemBuilder: (_) => pending
          ? [
              if ((m['body'] as String? ?? '').trim().isNotEmpty)
                const PopupMenuItem(value: 'copy', child: Text('Copy text')),
              const PopupMenuItem(
                value: 'discard',
                child: Text('Discard queued message'),
              ),
            ]
          : [
              if (!deleted) ...[
                if ((m['body'] as String? ?? '').trim().isNotEmpty)
                  const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                const PopupMenuItem(value: 'reply', child: Text('Reply')),
                const PopupMenuItem(
                  value: 'star',
                  child: Text('Star / unstar'),
                ),
                for (final emoji in ['❤️', '👍', '😂', '😮', '😢', '🙏'])
                  PopupMenuItem(value: 'react:$emoji', child: Text(emoji)),
                if (mine) ...[
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete for everyone'),
                  ),
                ],
              ],
              const PopupMenuItem(value: 'hide', child: Text('Delete for me')),
            ],
    );
  }

  Widget messageBubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == repo.uid;
    final deleted = m['deleted_at'] != null, pending = m['pending'] == true;
    final profile = repo.profiles[m['sender_id']];
    final reactions = pulseReactionCounts(
      repo.reactions.where((r) => r['message_id'] == m['id']),
    );
    final star = repo.preferences.any(
      (p) => p['message_id'] == m['id'] && p['starred'] == true,
    );
    final receipt = pulseReceipt(m, repo.receipts, repo.uid);
    final ownRead = repo.receipts.any(
      (r) =>
          r['message_id'] == m['id'] &&
          r['user_id'] == repo.uid &&
          r['read_at'] != null,
    );
    final replied = repo.messages
        .where((r) => r['id'] == m['reply_to'])
        .firstOrNull;
    final replyAuthor = replied == null
        ? null
        : repo.profiles[replied['sender_id']];
    final time = DateTime.tryParse(m['created_at'] ?? '')?.toLocal();
    final clock = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final style = repo.chatStyle;
    final accents = switch (style) {
      'aurora' => const [Color(0xffb9f6df), Color(0xffbfe8ff)],
      'rose' => const [Color(0xffffdce8), Color(0xffe9d9ff)],
      'ocean' => const [Color(0xffc2e9ff), Color(0xffcbd6ff)],
      _ => <Color>[],
    };
    final cs = Theme.of(context).colorScheme;
    final icon = switch (receipt) {
      PulseReceipt.queued => Icons.schedule,
      PulseReceipt.failed => Icons.error_outline,
      PulseReceipt.sent => Icons.check,
      _ => Icons.done_all,
    };
    final label = switch (receipt) {
      PulseReceipt.queued => 'Queued',
      PulseReceipt.failed => 'Could not send',
      PulseReceipt.sent => 'Sent',
      PulseReceipt.delivered => 'Delivered',
      PulseReceipt.read => 'Read by at least one recipient',
    };
    final visual =
        !deleted &&
        m['attachment_path'] is String &&
        ['image', 'video'].contains(
          m['media_kind'] ?? kindFor(mimeFor(m['attachment_path'] ?? '')),
        );
    final roundVideo = (m['attachment_path'] as String? ?? '').endsWith(
      '-pulse_note.mp4',
    );
    final caption = (m['body'] as String? ?? '').trim().isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaWidth = (constraints.maxWidth - (mine ? 0 : 42) - 8)
            .clamp(40.0, 460.0)
            .toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                GestureDetector(
                  onTap: () => openProfile(m['sender_id']),
                  child: PulseAvatar(
                    repo: repo,
                    path: profile?['avatar_path'],
                    name: profile?['display_name'] ?? 'P',
                    radius: 17,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      padding: visual
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.fromLTRB(14, 10, 4, 8),
                      decoration: BoxDecoration(
                        color: mine
                            ? cs.primaryContainer
                            : cs.surfaceContainerHigh,
                        gradient: mine && accents.isNotEmpty
                            ? LinearGradient(colors: accents)
                            : null,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DefaultTextStyle.merge(
                        style: mine && accents.isNotEmpty
                            ? const TextStyle(color: Color(0xff172831))
                            : const TextStyle(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!deleted && m['forwarded'] == true)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(6, 4, 6, 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.forward_rounded, size: 14),
                                          SizedBox(width: 5),
                                          Text(
                                            'Forwarded',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!deleted && m['status_id'] != null)
                                    InkWell(
                                      onTap: () => openStatusReference(
                                        m['status_id'] as String,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.donut_large,
                                              size: 18,
                                              color: cs.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            const Flexible(
                                              child: Text(
                                                'Status reply · View status',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (m['reply_to'] != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: cs.primary,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Reply to ${replyAuthor?['display_name'] ?? 'a message'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (replied != null)
                                            Text(
                                              replied['deleted_at'] != null
                                                  ? 'Message deleted'
                                                  : replied['body'],
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (!visual || caption)
                                    Text(
                                      deleted ? 'Message deleted' : m['body'],
                                      style: TextStyle(
                                        fontStyle: deleted
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                    ),
                                  if (!deleted &&
                                      RegExp(
                                        r'pulse:post:([0-9a-f-]{36})',
                                      ).hasMatch(m['body'] as String))
                                    TextButton.icon(
                                      onPressed: () => openSocialPost(
                                        context,
                                        social,
                                        RegExp(
                                          r'pulse:post:([0-9a-f-]{36})',
                                        ).firstMatch(m['body'])!.group(1)!,
                                      ),
                                      icon: const Icon(Icons.article_outlined),
                                      label: const Text('Open Pulse post'),
                                    ),
                                  if (!deleted && m['attachment_path'] != null)
                                    Stack(
                                      children: [
                                        PulseAttachment(
                                          key: ValueKey(m['id']),
                                          repo: repo,
                                          message: m,
                                          inlinePreview: visual,
                                          width: roundVideo
                                              ? mediaWidth
                                                    .clamp(40.0, 280.0)
                                                    .toDouble()
                                              : visual
                                              ? mediaWidth
                                              : 260,
                                          height: roundVideo
                                              ? mediaWidth
                                                    .clamp(40.0, 280.0)
                                                    .toDouble()
                                              : visual
                                              ? mediaWidth * .8
                                              : 180,
                                        ),
                                        if (visual)
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: Material(
                                              color: Colors.black45,
                                              shape: const CircleBorder(),
                                              child: IconTheme(
                                                data: const IconThemeData(
                                                  color: Colors.white,
                                                ),
                                                child: chatMessageMenu(m),
                                              ),
                                            ),
                                          ),
                                        if (visual && !caption)
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    clock,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  if (star)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.star_rounded,
                                                        size: 12,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  const SizedBox(width: 5),
                                                  Tooltip(
                                                    message: mine
                                                        ? label
                                                        : ownRead
                                                        ? 'Read by you'
                                                        : 'Unread',
                                                    child: Icon(
                                                      mine
                                                          ? icon
                                                          : ownRead
                                                          ? Icons
                                                                .check_circle_outline
                                                          : Icons
                                                                .circle_outlined,
                                                      size: 15,
                                                      color:
                                                          (mine &&
                                                                  receipt ==
                                                                      PulseReceipt
                                                                          .read ||
                                                              !mine && ownRead)
                                                          ? const Color(
                                                              0xff67d8f5,
                                                            )
                                                          : Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  if (!visual || caption)
                                    const SizedBox(height: 5),
                                  if (!visual || caption)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (star)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 4),
                                            child: Icon(
                                              Icons.star_rounded,
                                              size: 12,
                                            ),
                                          ),
                                        Text(
                                          '${m['edited_at'] != null ? 'edited · ' : ''}$clock',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: mine && accents.isNotEmpty
                                                ? const Color(0xff374a55)
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Tooltip(
                                          message: mine
                                              ? label
                                              : ownRead
                                              ? 'Read by you'
                                              : 'Unread',
                                          child: Icon(
                                            mine
                                                ? icon
                                                : ownRead
                                                ? Icons.check_circle_outline
                                                : Icons.circle_outlined,
                                            size: 15,
                                            color:
                                                (mine &&
                                                        receipt ==
                                                            PulseReceipt
                                                                .read) ||
                                                    (!mine && ownRead)
                                                ? const Color(0xff139bba)
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (!visual) chatMessageMenu(m),
                          ],
                        ),
                      ),
                    ),
                    if (!deleted && reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            for (final r in reactions.entries)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  '${r.key}${r.value > 1 ? ' ${r.value}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (!mine && !visual) const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> openStatusChat(String chat) async {
    await repo.openChat(chat);
    if (mounted)
      setState(() {
        section = 0;
        socialSection = 3;
      });
  }

  Future<void> openStatusReference(String id) async {
    try {
      final status = await repo.db
          .from('pulse_statuses')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (!mounted) return;
      if (status == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This status has expired, was deleted, or is unavailable.',
            ),
          ),
        );
        return;
      }
      final chat = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => StatusViewer(repo: repo, status: status),
        ),
      );
      if (chat != null && mounted) await openStatusChat(chat);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this status. Check your connection.'),
          ),
        );
    }
  }

  Widget updatesView() => StatusUpdates(
    repo: repo,
    updates: channelUpdates,
    onChat: openStatusChat,
  );
  Widget groupsView() => PulseCommunities(
    repo: repo,
    onChat: (id) {
      repo.openChat(id);
      setState(() {
        section = 0;
        socialSection = 3;
      });
    },
  );

  Future<void> confirmSignOut({bool all = false}) async {
    final count = repo.pending.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(all ? 'Sign out all devices?' : 'Sign out this device?'),
        content: Text(
          [
            if (count > 0)
              '$count unsent message(s) on this device will be removed. Cancel to send them first.',
            'The saved chat cache on this device will be removed.',
            if (all)
              'Refresh sessions on other devices will be revoked. Existing access tokens remain valid until expiry.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await perform(() => repo.signOut(all: all));
  }

  Widget settingsView() => ListView(
    children: [
      header('Settings'),
      ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: const Text('Gifter ranks'),
        subtitle: const Text('10 ranks · badge and spending privacy'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseGifterRanksPage(repo: repo)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.mail_outline),
        title: const Text('Pulse mail & requests'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseMailbox(repo: repo)),
        ),
      ),
      ListTile(
        leading: PulseActivityButton(store: social),
        title: const Text('Activity notifications'),
        subtitle: const Text('Tags, followers, likes and new posts'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseActivityPage(store: social)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('Help & support'),
        subtitle: const Text('Contact Pulse support'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseHelpPage(repo: repo)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.policy_outlined),
        title: const Text('Privacy Policy'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PulsePrivacyPage()),
        ),
      ),
      FutureBuilder<dynamic>(
        future: repo.rpc('is_admin', {}),
        builder: (_, snapshot) => snapshot.data == true
            ? ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Administrator dashboard'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminScreen(repo: repo)),
                ),
              )
            : const SizedBox.shrink(),
      ),
      if (repo.me != null)
        ListTile(
          leading: PulseAvatar(
            repo: repo,
            path: repo.me!['avatar_path'],
            name: repo.me!['display_name'],
          ),
          title: Text(repo.me!['display_name']),
          subtitle: Text('@${repo.me!['username'] ?? 'choose_username'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Your profile')),
                body: ProfilePanel(
                  repo: repo,
                  onSaved: () async {
                    await repo.refresh();
                    if (mounted) Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.circle_outlined),
        title: const Text('Active status'),
        subtitle: const Text('Online and last seen privacy'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PulsePresenceSettings(presence: repo.presence),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Themes & wallpapers'),
        subtitle: const Text('Wallpapers, matching colors, splash and loading'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PulseAppearancePage()),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.dark_mode_outlined),
        title: const Text('Dark / light theme'),
        onTap: widget.toggleTheme,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Message notifications'),
        subtitle: Text(
          PulsePush.instance.status ??
              'Alerts while Pulse is running. Windows closed-app push is not configured.',
        ),
        value: PulseNotifications.instance.enabled,
        onChanged: (value) async {
          await perform(() => PulseNotifications.instance.setEnabled(value));
        },
      ),
      ListTile(
        leading: const Icon(Icons.notification_add_outlined),
        title: const Text('Test notification'),
        onTap: () async {
          final ok = await PulseNotifications.instance.test();
          notice(
            ok
                ? 'Notification requested. Check your device alerts.'
                : 'Notifications are disabled or unavailable. Check system permissions.',
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Change password'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PasswordSettingsPage(client: repo.db),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.block),
        title: const Text('Blocked accounts'),
        subtitle: Text('${repo.blocks.length} blocked'),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const Text('Blocked accounts'),
              children: repo.blocks
                  .map(
                    (b) => SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(c);
                        perform(() async {
                          await repo.rpc('block_user', {
                            'p_user': b['blocked_id'],
                            'p_block': false,
                          });
                          social.hiddenCreators.remove(b['blocked_id']);
                        });
                      },
                      child: Text(
                        'Unblock ${repo.profiles[b['blocked_id']]?['display_name'] ?? b['blocked_id']}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('Download your data'),
        subtitle: const Text('Export accessible messages and your content'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AccountExportPage(repo: repo)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.health_and_safety_outlined),
        title: const Text('Diagnostics'),
        subtitle: const Text('Connection, pending messages and configuration'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseDiagnosticsPage(repo: repo)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign out this device'),
        onTap: () => confirmSignOut(),
      ),
      ListTile(
        leading: const Icon(Icons.devices),
        title: const Text('Sign out all devices'),
        subtitle: const Text(
          'Revokes refresh sessions; existing access tokens expire normally.',
        ),
        onTap: () => confirmSignOut(all: true),
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'PULSE 0.5.5 · Private beta\nMessages are protected by access policies and TLS. End-to-end encryption, individual device management and MFA UI are not implemented yet. Do not use this beta for sensitive conversations.',
        ),
      ),
    ],
  );
}

class FeatureNotice extends StatelessWidget {
  const FeatureNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
