import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avatar.dart';
import 'call_tone.dart';
import 'call_signal.dart';
import 'notifications.dart';
import 'repository.dart' hide Row;

typedef CallRow = Map<String, dynamic>;

String callError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is FunctionException) {
    if (error.status == 503)
      return 'Calls need LiveKit setup. Add LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET in Supabase Edge Function secrets.';
    if (error.status == 401) return 'Your session expired. Sign in again.';
    final details = error.details;
    if (details is Map && details['error'] is String)
      return details['error'] as String;
  }
  return 'Call failed. Check your connection, LiveKit setup and microphone/camera permissions.';
}

class PulseCalls extends ChangeNotifier {
  PulseCalls(this.repo);
  final PulseRepository repo;
  List<CallRow> history = [];
  String? error;
  bool busy = false, disposed = false;
  Timer? timer;
  RealtimeChannel? realtime;
  final notified = <String>{};
  final received = <String>{};
  final incomingTone = PulseCallTone();

  void start() {
    refresh();
    realtime = repo.db
        .channel('pulse-calls:${repo.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_calls',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_call_members',
          callback: (_) => refresh(),
        )
        .subscribe();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
  }

  List<CallRow> members(CallRow call) =>
      (call['pulse_call_members'] as List? ?? call['members'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
  CallRow? ownMember(CallRow call) {
    final match = members(call).where((x) => x['user_id'] == repo.uid);
    return match.isEmpty ? null : match.first;
  }

  CallRow? get incoming {
    for (final call in history) {
      if (call['status'] != 'ended' &&
          ownMember(call)?['state'] == 'ringing' &&
          DateTime.parse(call['ring_deadline']).isAfter(DateTime.now().toUtc()))
        return call;
    }
    return null;
  }

  CallRow? get ongoing {
    for (final call in history) {
      if (call['status'] != 'ended' &&
          ownMember(call)?['state'] == 'joined' &&
          DateTime.parse(call['expires_at']).isAfter(DateTime.now().toUtc()))
        return call;
    }
    return null;
  }

  Future<void> refresh() async {
    if (disposed || busy || repo.db.auth.currentUser == null) return;
    busy = true;
    try {
      final rows = await repo.db
          .from('pulse_calls')
          .select('*,pulse_call_members(*)')
          .order('created_at', ascending: false)
          .limit(100);
      if (disposed) return;
      history = rows;
      error = null;
      final call = incoming;
      if (call != null && !received.contains(call['id'])) {
        final acknowledged = await repo.rpc('call_received', {
          'p_call': call['id'],
        });
        if (acknowledged == true) received.add(call['id']);
      }
      if (disposed) return;
      unawaited(
        incomingTone.play(
          call != null && PulseNotifications.instance.enabled
              ? 'incoming'
              : null,
        ),
      );
      if (call != null && notified.add(call['id'])) {
        if (notified.length > 200) notified.remove(notified.first);
        unawaited(
          PulseNotifications.instance.incomingCall(
            call['id'],
            call['kind'] == 'video',
          ),
        );
      }
    } catch (_) {
      unawaited(incomingTone.play(null));
      if (!disposed) error = 'Call history is offline. Reconnect to refresh.';
    } finally {
      busy = false;
      if (!disposed) notifyListeners();
    }
  }

  Future<CallRow> invoke(
    String action, {
    String? chatId,
    String? callId,
    String? kind,
  }) async {
    final response = await repo.db.functions.invoke(
      'pulse-call',
      body: {
        'action': action,
        if (chatId != null) 'chat_id': chatId,
        if (callId != null) 'call_id': callId,
        if (kind != null) 'kind': kind,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> decline(String callId) async {
    try {
      await invoke('decline', callId: callId);
    } catch (_) {
      await repo.rpc('call_leave', {'p_call': callId, 'p_decline': true});
    }
    await refresh();
  }

  @override
  void dispose() {
    disposed = true;
    incomingTone.dispose();
    timer?.cancel();
    if (realtime != null) unawaited(repo.db.removeChannel(realtime!));
    super.dispose();
  }
}

class CallsList extends StatelessWidget {
  const CallsList({super.key, required this.calls, required this.open});
  final PulseCalls calls;
  final Future<void> Function(CallRow call) open;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Calls',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Refresh calls',
              onPressed: calls.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Start a voice or video call from a chat. Calls support up to 8 chat members. Incoming calls appear when your device receives the invitation. Closed-app alerts require configured Android push notifications.',
        ),
      ),
      if (calls.error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(calls.error!)),
      Expanded(
        child: ListView(
          children: [
            if (calls.history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Your calls will appear here.'),
              ),
            for (final call in calls.history)
              ListTile(
                leading: Icon(
                  call['kind'] == 'video'
                      ? Icons.videocam_outlined
                      : Icons.call_outlined,
                ),
                title: Text(
                  calls.repo.profiles[call['caller_id']]?['display_name'] ??
                      'Pulse call',
                ),
                subtitle: Text(
                  '${call['caller_id'] == calls.repo.uid ? 'Outgoing' : 'Incoming'} · ${call['status'] == 'ended' ? (call['ended_reason'] ?? 'Ended') : call['status']}\n${DateTime.parse(call['created_at']).toLocal().toString().substring(0, 16)}',
                ),
                isThreeLine: true,
                trailing:
                    call['status'] != 'ended' &&
                        (calls.ownMember(call)?['state'] == 'joined' ||
                            calls.ownMember(call)?['state'] == 'ringing')
                    ? TextButton(
                        onPressed: () => open(call),
                        child: const Text('Open'),
                      )
                    : null,
              ),
          ],
        ),
      ),
    ],
  );
}

class PulseCallScreen extends StatefulWidget {
  const PulseCallScreen({
    super.key,
    required this.calls,
    required this.credentials,
  });
  final PulseCalls calls;
  final CallRow credentials;
  @override
  State<PulseCallScreen> createState() => _PulseCallScreenState();
}

class _PulseCallScreenState extends State<PulseCallScreen>
    with WidgetsBindingObserver {
  final room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  late CallRow state;
  final outboundTone = PulseCallTone();
  Timer? timer;
  bool connected = false,
      muted = false,
      camera = false,
      speaker = false,
      ending = false,
      polling = false,
      controlsBusy = false;
  int deviceIndex = 0;
  String? error;
  String get id => state['id'];
  PulseRepository get repo => widget.calls.repo;

  @override
  void initState() {
    super.initState();
    state = Map<String, dynamic>.from(widget.credentials['call']);
    WidgetsBinding.instance.addObserver(this);
    room.addListener(changed);
    connect(widget.credentials);
  }

  void changed() {
    syncTone();
    if (mounted) setState(() {});
  }

  void syncTone() {
    final label = pulseCallSignal(state, repo.uid, DateTime.now());
    unawaited(
      outboundTone.play(
        !ending &&
                connected &&
                state['caller_id'] == repo.uid &&
                room.remoteParticipants.isEmpty &&
                state['status'] == 'ringing'
            ? (label == 'Ringing…'
                  ? 'ringback'
                  : label == 'Calling…'
                  ? 'calling'
                  : null)
            : null,
      ),
    );
  }

  Future<void> connect(CallRow credentials) async {
    try {
      await room.connect(credentials['url'], credentials['token']);
      if (!mounted || ending) {
        await room.disconnect();
        return;
      }
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (state['kind'] == 'video') {
        await room.localParticipant?.setCameraEnabled(true);
        camera = true;
      }
      speaker = state['kind'] == 'video';
      await lk.AudioManager.instance.setSpeakerOutputPreferred(speaker);
      if (!mounted || ending) {
        await room.disconnect();
        return;
      }
      setState(() {
        connected = true;
        error = null;
      });
      timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
      await poll();
      syncTone();
    } catch (e) {
      await room.disconnect();
      try {
        await widget.calls.invoke('leave', callId: id);
      } catch (_) {}
      if (mounted)
        setState(() {
          connected = false;
          error = callError(e);
        });
    }
  }

  Future<void> poll() async {
    if (polling || ending) return;
    polling = true;
    try {
      final snapshot = Map<String, dynamic>.from(
        await repo.rpc('call_state', {'p_call': id, 'p_touch': true}) as Map,
      );
      if (!mounted || ending) return;
      final me = (snapshot['members'] as List).where(
        (m) => m['user_id'] == repo.uid,
      );
      if (snapshot['status'] == 'ended' ||
          me.isEmpty ||
          me.first['state'] != 'joined') {
        await leave();
        return;
      }
      setState(() {
        state = snapshot;
        error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Connection lost. Trying to reconnect…');
      if (DateTime.parse(state['expires_at']).isBefore(DateTime.now().toUtc()))
        await leave();
    } finally {
      polling = false;
      syncTone();
    }
  }

  Future<void> control(Future<void> Function() action) async {
    if (controlsBusy || !connected || ending) return;
    setState(() => controlsBusy = true);
    try {
      await action();
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not change this device control. Check permissions.',
        );
    } finally {
      if (mounted) setState(() => controlsBusy = false);
    }
  }

  Future<void> leave() async {
    if (ending) return;
    ending = true;
    unawaited(outboundTone.play(null));
    timer?.cancel();
    await room.disconnect();
    try {
      await widget.calls.invoke('leave', callId: id);
    } catch (_) {
      try {
        await repo.rpc('call_leave', {'p_call': id, 'p_decline': false});
      } catch (_) {}
    }
    await widget.calls.refresh();
    if (mounted) Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // No Android foreground-call service is shipped in this beta. Release media explicitly.
    if (Platform.isAndroid && lifecycle == AppLifecycleState.paused)
      unawaited(leave());
  }

  @override
  void dispose() {
    outboundTone.dispose();
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    room.removeListener(changed);
    // Account changes remove routes. Dispose native media in order and do not
    // issue an unauthenticated leave request after sign-out.
    unawaited(() async {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
      if (!ending && repo.db.auth.currentUser != null) {
        try {
          await repo.rpc('call_leave', {'p_call': id, 'p_decline': false});
        } catch (_) {}
      }
    }());
    super.dispose();
  }

  Widget tile(lk.Participant participant) {
    lk.VideoTrack? video;
    for (final publication in participant.videoTrackPublications) {
      if (!publication.muted && publication.track is lk.VideoTrack) {
        video = publication.track as lk.VideoTrack;
        break;
      }
    }
    final person = repo.profiles[participant.identity];
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              lk.VideoTrackRenderer(video)
            else
              Center(
                child: PulseAvatar(
                  repo: repo,
                  path: person?['avatar_path'],
                  name: person?['display_name'] ?? 'P',
                  radius: 40,
                ),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                color: Colors.black54,
                child: Text(
                  participant.identity == repo.uid
                      ? 'You'
                      : person?['display_name'] ?? 'Pulse user',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    final started = state['started_at'] == null
        ? null
        : DateTime.parse(state['started_at']);
    final seconds = started == null
        ? 0
        : DateTime.now().toUtc().difference(started).inSeconds;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            state['kind'] == 'video' ? 'Pulse video call' : 'Pulse voice call',
          ),
          leading: IconButton(
            onPressed: leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Transport encrypted · End-to-end encryption is not implemented',
              ),
            ),
            Text(
              !connected
                  ? 'Connecting…'
                  : room.connectionState == lk.ConnectionState.reconnecting
                  ? 'Reconnecting…'
                  : state['status'] == 'ringing'
                  ? pulseCallSignal(state, repo.uid, DateTime.now())
                  : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} · ${room.remoteParticipants.length + 1} connected',
            ),
            if (error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Expanded(
              child: !connected
                  ? Center(
                      child: error == null
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.call_end, size: 64),
                    )
                  : GridView.count(
                      crossAxisCount: people.length > 1 ? 2 : 1,
                      padding: const EdgeInsets.all(16),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      children: people.map(tile).toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: muted ? 'Unmute microphone' : 'Mute microphone',
                    onPressed: controlsBusy
                        ? null
                        : () => control(() async {
                            await room.localParticipant?.setMicrophoneEnabled(
                              muted,
                            );
                            muted = !muted;
                          }),
                    icon: Icon(muted ? Icons.mic_off : Icons.mic),
                  ),
                  if (state['kind'] == 'video')
                    IconButton.filledTonal(
                      tooltip: camera ? 'Turn camera off' : 'Turn camera on',
                      onPressed: controlsBusy
                          ? null
                          : () => control(() async {
                              await room.localParticipant?.setCameraEnabled(
                                !camera,
                              );
                              camera = !camera;
                            }),
                      icon: Icon(camera ? Icons.videocam : Icons.videocam_off),
                    ),
                  if (state['kind'] == 'video')
                    IconButton.filledTonal(
                      tooltip: 'Switch camera',
                      onPressed: controlsBusy
                          ? null
                          : () => control(() async {
                              final devices = await lk.Hardware.instance
                                  .videoInputs();
                              if (devices.length < 2)
                                throw Exception('No second camera');
                              deviceIndex = (deviceIndex + 1) % devices.length;
                              await room.setVideoInputDevice(
                                devices[deviceIndex],
                              );
                            }),
                      icon: const Icon(Icons.cameraswitch),
                    ),
                  if (Platform.isAndroid)
                    IconButton.filledTonal(
                      tooltip: 'Speaker output',
                      onPressed: controlsBusy
                          ? null
                          : () => control(() async {
                              await lk.AudioManager.instance
                                  .setSpeakerOutputPreferred(!speaker);
                              speaker = !speaker;
                            }),
                      icon: Icon(speaker ? Icons.volume_up : Icons.hearing),
                    ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    tooltip: 'Leave call',
                    onPressed: leave,
                    icon: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
