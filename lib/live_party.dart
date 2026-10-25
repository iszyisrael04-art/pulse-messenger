import 'gift_face_anchor.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'repository.dart' hide Row;
import 'avatar.dart';
import 'social_common.dart';

class PulseLiveParty extends ChangeNotifier {
  PulseLiveParty(this.repo, this.session);
  final PulseRepository repo;
  final String session;
  Map<String, dynamic> data = {};
  bool busy = false, disposed = false;
  String get state => data['state']?.toString() ?? 'none';
  String get mode => data['mode']?.toString() ?? 'video';
  List<Map<String, dynamic>> get members => [
    if (data['host'] is Map) Map<String, dynamic>.from(data['host'] as Map),
    for (final m in data['members'] as List? ?? [])
      Map<String, dynamic>.from(m as Map),
  ];
  List<Map<String, dynamic>> get requests => [
    for (final m in data['requests'] as List? ?? [])
      Map<String, dynamic>.from(m as Map),
  ];
  Future<void> refresh() async {
    final info = await repo.rpc('live_party', {
      'p_action': 'info',
      'p_session': session,
    });
    if (disposed) return;
    data = Map<String, dynamic>.from(info as Map);
    notifyListeners();
  }

  Future<void> action(
    String action, {
    String? user,
    String mode = 'video',
  }) async {
    if (busy || disposed) return;
    busy = true;
    notifyListeners();
    try {
      await repo.db.functions.invoke(
        'pulse-live',
        body: {
          'action': 'party',
          'party_action': action,
          'session_id': session,
          'user_id': user,
          'mode': mode,
        },
      );
      await refresh();
    } finally {
      busy = false;
      if (!disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> sync({bool reconcile = false}) async {
    final r = await repo.db.functions.invoke(
      'pulse-live',
      body: {
        'action': 'party-sync',
        'session_id': session,
        'reconcile': reconcile,
      },
    );
    return Map<String, dynamic>.from(r.data as Map);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Future<void> showPulsePartyRequests(
  BuildContext context,
  PulseLiveParty party,
) async {
  try {
    await party.refresh();
  } catch (e) {
    if (context.mounted) socialNotice(context, e);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .65,
        child: AnimatedBuilder(
          animation: party,
          builder: (_, __) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'LIVE Party',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${party.members.length}/9 seats · guests choose audio or video',
              ),
              const SizedBox(height: 20),
              const Text(
                'Requests',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (party.requests.isEmpty)
                const ListTile(title: Text('No pending requests')),
              for (final request in party.requests)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: PulseAvatar(
                    repo: party.repo,
                    path: request['avatar_path'],
                    name: request['display_name'],
                  ),
                  title: Text(
                    request['display_name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    request['mode'] == 'audio' ? 'Audio seat' : 'Video seat',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Approve guest',
                        onPressed: party.busy
                            ? null
                            : () async {
                                try {
                                  await party.action(
                                    'approve',
                                    user: request['user_id'],
                                  );
                                } catch (e) {
                                  if (sheet.mounted) socialNotice(sheet, e);
                                }
                              },
                        icon: const Icon(Icons.check_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Decline request',
                        onPressed: party.busy
                            ? null
                            : () async {
                                try {
                                  await party.action(
                                    'reject',
                                    user: request['user_id'],
                                  );
                                } catch (e) {
                                  if (sheet.mounted) socialNotice(sheet, e);
                                }
                              },
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 32),
              const Text(
                'On stage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final member in party.members)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: PulseAvatar(
                    repo: party.repo,
                    path: member['avatar_path'],
                    name: member['display_name'],
                  ),
                  title: Text(
                    member['display_name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    member['host'] == true
                        ? 'Host'
                        : member['mode'] == 'audio'
                        ? 'Audio guest'
                        : 'Video guest',
                  ),
                  trailing: member['host'] == true
                      ? null
                      : IconButton(
                          tooltip: 'Remove guest from stage',
                          onPressed: party.busy
                              ? null
                              : () async {
                                  try {
                                    await party.action(
                                      'remove',
                                      user: member['user_id'],
                                    );
                                  } catch (e) {
                                    if (sheet.mounted) socialNotice(sheet, e);
                                  }
                                },
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PulsePartyGrid extends StatelessWidget {
  const PulsePartyGrid({
    super.key,
    required this.room,
    required this.party,
    this.crownUntil,
  });
  final DateTime? crownUntil;
  final lk.Room room;
  final PulseLiveParty party;
  @override
  Widget build(BuildContext context) {
    final members = party.members;
    if (members.isEmpty)
      return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, bounds) {
        final columns = members.length == 1
            ? 1
            : members.length <= 4
            ? 2
            : 3;
        final rows = (members.length / columns).ceil();
        final width = (bounds.maxWidth - (columns - 1) * 4) / columns;
        final height = (bounds.maxHeight - (rows - 1) * 4) / rows;
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: width / (height > 0 ? height : 1),
          ),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            lk.VideoTrack? video;
            final local = room.localParticipant;
            if (local?.identity == member['user_id']) {
              for (final publication in local?.videoTrackPublications ?? []) {
                if (publication.track is lk.VideoTrack && !publication.muted) {
                  video = publication.track as lk.VideoTrack;
                  break;
                }
              }
            } else {
              for (final remote in room.remoteParticipants.values) {
                if (remote.identity != member['user_id']) continue;
                for (final publication in remote.videoTrackPublications) {
                  if (publication.track is lk.VideoTrack &&
                      !publication.muted) {
                    video = publication.track as lk.VideoTrack;
                    break;
                  }
                }
              }
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xff151b29)),
                  if (video != null)
                    if (member['host'] == true &&
                        crownUntil != null &&
                        crownUntil!.isAfter(DateTime.now()))
                      PulseHeadCrown(
                        key: ValueKey('crown:${video.mediaStreamTrack.id}'),
                        until: crownUntil!,
                        sample: () => pulseSampleFace(video!),
                        mirror:
                            video is lk.LocalVideoTrack &&
                            (video.mediaStreamTrack
                                        .getSettings()['facingMode'] ==
                                    'user' ||
                                (video.currentOptions
                                        is lk.CameraCaptureOptions &&
                                    (video.currentOptions
                                                as lk.CameraCaptureOptions)
                                            .cameraPosition ==
                                        lk.CameraPosition.front)),
                        child: lk.VideoTrackRenderer(video),
                      )
                    else
                      lk.VideoTrackRenderer(video)
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PulseAvatar(
                            repo: party.repo,
                            path: member['avatar_path'],
                            name: member['display_name'],
                            radius: 24,
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            member['mode'] == 'audio'
                                ? Icons.mic_none
                                : Icons.videocam_off_outlined,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
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
                          '${member['host'] == true ? 'Host · ' : ''}${member['display_name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
