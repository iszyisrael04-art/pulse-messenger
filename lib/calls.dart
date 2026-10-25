import 'call_layout.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
  String? alertingCall;

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
      if (alertingCall != null && alertingCall != call?['id']) {
        unawaited(PulseNotifications.instance.clearCall(alertingCall!));
      }
      alertingCall = call?['id'];
      if (call != null && !received.contains(call['id'])) {
        final acknowledged = await repo.rpc('call_received', {
          'p_call': call['id'],
        });
        if (acknowledged == true) received.add(call['id']);
      }
      if (disposed) return;
      unawaited(
        incomingTone.play(
          call != null &&
                  PulseNotifications.instance.enabled &&
                  !Platform.isAndroid
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
  Timer? timer, elapsedTimer;
  Future<void>? shutdownFuture;
  late final String selfId;
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
    selfId = repo.uid;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !ending && state['status'] == 'active') setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    room.addListener(changed);
    connect(widget.credentials);
  }

  void changed() {
    if (!mounted || ending) return;
    syncTone();
    if (mounted) setState(() {});
  }

  void syncTone() {
    if (!mounted || ending) return;
    final label = pulseCallSignal(state, selfId, DateTime.now());
    unawaited(
      outboundTone.play(
        !ending &&
                connected &&
                state['caller_id'] == selfId &&
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
      if (!mounted || ending) {
        await room.disconnect();
        return;
      }
      if (state['kind'] == 'video') {
        await room.localParticipant?.setCameraEnabled(true);
        camera = true;
      }
      if (!mounted || ending) {
        await room.disconnect();
        return;
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
      if (!mounted || ending) return;
      setState(() {
        connected = false;
        error = callError(e);
      });
      shutdownFuture ??= shutdown();
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
        (m) => m['user_id'] == selfId,
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

  Future<void> leaveServer() async {
    // A removed account route must never send a leave request as another user.
    if (repo.db.auth.currentUser?.id != selfId) return;
    try {
      await widget.calls
          .invoke('leave', callId: id)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        if (repo.db.auth.currentUser?.id == selfId) {
          await repo
              .rpc('call_leave', {'p_call': id, 'p_decline': false})
              .timeout(const Duration(seconds: 4));
        }
      } catch (_) {}
    }
    try {
      await widget.calls.refresh().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> shutdown() async {
    timer?.cancel();
    elapsedTimer?.cancel();
    final server = leaveServer();
    await Future.wait([
      () async {
        try {
          await room.localParticipant
              ?.setCameraEnabled(false)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }(),
      () async {
        try {
          await room.localParticipant
              ?.setMicrophoneEnabled(false)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }(),
    ]);
    try {
      await room.disconnect().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await room.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await server;
  }

  Future<void> leave() async {
    if (ending) return;
    setState(() => ending = true);
    unawaited(outboundTone.play(null));
    timer?.cancel();
    elapsedTimer?.cancel();
    // UI closes on the next frame; server and native device cleanup are bounded.
    shutdownFuture ??= shutdown();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) pulseCloseCallRoute(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    unawaited(
      (lifecycle == AppLifecycleState.resumed && !ending
              ? WakelockPlus.enable()
              : WakelockPlus.disable())
          .catchError((_) {}),
    );
    // The current Android beta releases media in background; no foreground-call
    // service or system picture-in-picture is implied by this in-call preview.
    if (Platform.isAndroid &&
        lifecycle == AppLifecycleState.paused &&
        !ending) {
      unawaited(leave());
    }
  }

  @override
  void dispose() {
    outboundTone.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable().catchError((_) {}));
    timer?.cancel();
    elapsedTimer?.cancel();
    room.removeListener(changed);
    shutdownFuture ??= shutdown();
    super.dispose();
  }

  Future<void> switchCamera() => control(() async {
    final track = room.localParticipant?.videoTrackPublications
        .map((p) => p.track)
        .whereType<lk.LocalVideoTrack>()
        .firstOrNull;
    if (track == null) throw StateError('Camera is not active');
    if (Platform.isAndroid || Platform.isIOS) {
      final options = track.currentOptions;
      final facing = track.mediaStreamTrack.getSettings()['facingMode'];
      final front = facing == null
          ? options is lk.CameraCaptureOptions &&
                options.cameraPosition == lk.CameraPosition.front
          : facing == 'user';
      await track.setCameraPosition(
        front ? lk.CameraPosition.back : lk.CameraPosition.front,
      );
    } else {
      final devices = await lk.Hardware.instance.videoInputs();
      if (devices.length < 2) throw StateError('No second camera');
      final current = track.mediaStreamTrack
          .getSettings()['deviceId']
          ?.toString();
      final index = devices.indexWhere((d) => d.deviceId == current);
      deviceIndex = ((index >= 0 ? index : deviceIndex) + 1) % devices.length;
      await room.setVideoInputDevice(devices[deviceIndex]);
    }
  });

  Future<void> details() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Call information'),
      content: SingleChildScrollView(
        child: Text(
          '${error == null ? '' : '$error\n\n'}Media is encrypted in transit. End-to-end encryption is not implemented in this Pulse beta.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> participants() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .55,
        child: AnimatedBuilder(
          animation: Listenable.merge([room, widget.calls]),
          builder: (_, __) {
            final members = widget.calls.members(state);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Participants · ${members.length}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final member in members)
                  ListTile(
                    leading: PulseAvatar(
                      repo: repo,
                      path: repo.profiles[member['user_id']]?['avatar_path'],
                      name:
                          repo.profiles[member['user_id']]?['display_name'] ??
                          'Pulse user',
                    ),
                    title: Text(
                      member['user_id'] == selfId
                          ? 'You'
                          : repo.profiles[member['user_id']]?['display_name'] ??
                                'Pulse user',
                    ),
                    subtitle: Text(
                      member['state'] == 'ringing'
                          ? member['received_at'] == null
                                ? 'Calling…'
                                : 'Ringing…'
                          : member['state'] == 'joined'
                          ? 'Joined'
                          : member['state'] == 'declined'
                          ? 'Declined'
                          : 'Left',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget tile(
    lk.Participant participant, {
    bool fill = true,
    bool label = false,
  }) {
    final video = participant.videoTrackPublications
        .where((p) => !p.muted)
        .map((p) => p.track)
        .whereType<lk.VideoTrack>()
        .firstOrNull;
    final person = repo.profiles[participant.identity];
    final own = participant.identity == selfId;
    return ColoredBox(
      color: const Color(0xff142329),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null)
            lk.VideoTrackRenderer(
              video,
              fit: fill ? lk.VideoViewFit.cover : lk.VideoViewFit.contain,
            )
          else
            LayoutBuilder(
              builder: (_, box) {
                final radius = (box.biggest.shortestSide * .20).clamp(
                  14.0,
                  70.0,
                );
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulseAvatar(
                        repo: repo,
                        path: person?['avatar_path'],
                        name: person?['display_name'] ?? 'Pulse user',
                        radius: radius,
                      ),
                      if (box.maxHeight > 180 && state['kind'] == 'video') ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Camera off',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          if (label)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Text(
                    own ? 'You' : person?['display_name'] ?? 'Pulse user',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peers = room.remoteParticipants.values.toList();
    final local = room.localParticipant;
    final members = widget.calls
        .members(state)
        .where((m) => m['user_id'] != selfId)
        .toList();
    final peer = peers.firstOrNull;
    final lk.Participant? main = peer ?? local;
    final otherId = peer?.identity ?? members.firstOrNull?['user_id'];
    final chat = repo.chats
        .where((c) => c['id'] == state['chat_id'])
        .firstOrNull;
    final group = peers.length > 1;
    final name = members.length > 1
        ? (chat?['name'] as String? ?? 'Group call')
        : repo.profiles[otherId]?['display_name'] as String? ?? 'Pulse call';
    final started = DateTime.tryParse(state['started_at']?.toString() ?? '');
    final seconds = started == null
        ? 0
        : DateTime.now().toUtc().difference(started).inSeconds.clamp(0, 86400);
    final status = ending
        ? 'Ending…'
        : !connected
        ? error == null
              ? 'Connecting…'
              : 'Call unavailable'
        : room.connectionState == lk.ConnectionState.reconnecting
        ? 'Reconnecting…'
        : state['status'] == 'ringing'
        ? pulseCallSignal(state, selfId, DateTime.now())
        : peers.isEmpty
        ? 'Connecting media…'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}${group ? ' · ${peers.length + 1} connected' : ''}';
    return PopScope(
      canPop: ending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PulseCallLayout(
          name: name,
          status: status,
          videoCall: state['kind'] == 'video',
          muted: muted,
          camera: camera,
          speaker: speaker,
          ending: ending,
          controlsEnabled: connected && !controlsBusy && !ending,
          error: error,
          onDetails: details,
          onMembers: participants,
          onHangUp: leave,
          mainVideo: (fill) =>
              main != null && (state['kind'] == 'video' || peer != null)
              ? tile(main, fill: fill)
              : Center(
                  child: PulseAvatar(
                    repo: repo,
                    path: repo.profiles[otherId]?['avatar_path'],
                    name: name,
                    radius: 70,
                  ),
                ),
          previewVideo:
              !group &&
                  peer != null &&
                  local != null &&
                  state['kind'] == 'video'
              ? (fill) => tile(local, fill: fill)
              : null,
          groupVideos: group
              ? [
                  if (local != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: tile(local, label: true),
                    ),
                  for (final remote in peers)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: tile(remote, label: true),
                    ),
                ]
              : const [],
          onMute: () => control(() async {
            await room.localParticipant?.setMicrophoneEnabled(muted);
            muted = !muted;
          }),
          onCamera: state['kind'] == 'video'
              ? () => control(() async {
                  await room.localParticipant?.setCameraEnabled(!camera);
                  camera = !camera;
                })
              : null,
          onSwitchCamera: state['kind'] == 'video' ? switchCamera : null,
          onSpeaker: Platform.isAndroid || Platform.isIOS
              ? () => control(() async {
                  await lk.AudioManager.instance.setSpeakerOutputPreferred(
                    !speaker,
                  );
                  speaker = !speaker;
                })
              : null,
        ),
      ),
    );
  }
}
