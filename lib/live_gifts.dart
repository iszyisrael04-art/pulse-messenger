import 'gift_combo_feed.dart';
import 'gift_gallery.dart';
import 'gift_cinematic.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'repository.dart' hide Row;
import 'social_repository.dart' show socialError;
import 'shop.dart';

/// Same-room, consent-based three-minute battles. No wagers or prize payouts.
class PulseLiveGifts extends StatefulWidget {
  const PulseLiveGifts({
    super.key,
    required this.repo,
    required this.session,
    required this.host,
    this.onGift,
    this.onBattle,
    this.compact = false,
  });
  final PulseRepository repo;
  final String session;
  final bool host, compact;
  final ValueChanged<Map<String, dynamic>>? onGift;
  final ValueChanged<Map<String, dynamic>>? onBattle;
  @override
  State<PulseLiveGifts> createState() => PulseLiveGiftsState();
}

class PulseLiveGiftsState extends State<PulseLiveGifts> {
  Map<String, dynamic> gifts = {}, battle = {}, party = {};
  Timer? timer;
  bool loading = false, busy = false, choosing = false;
  String? error, feedAfter, feedCursor;
  bool readingFeed = false, pendingTest = false;
  int testCoins = 0;
  final seenGifts = <String>{};
  final comboFeed = PulseGiftComboFeed();
  Map<String, dynamic>? pendingGift;
  Map? comboGift;
  bool comboTest = false;
  int comboCount = 0;
  DateTime? comboUntil;
  bool get showCombo =>
      comboGift != null &&
      comboUntil != null &&
      comboUntil!.isAfter(DateTime.now());
  String? get hostId => (party['host'] as Map?)?['user_id'] as String?;
  List<Map> get people => [
    if (party['host'] is Map) party['host'] as Map,
    ...(party['members'] as List? ?? []).cast<Map>(),
  ];
  @override
  void initState() {
    super.initState();
    readFeed();
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      readFeed();
      load();
    });
  }

  Future<void> readFeed() async {
    if (readingFeed) return;
    readingFeed = true;
    try {
      final result = await widget.repo.rpc('gift_feed', {
        'p_session': widget.session,
        if (feedAfter != null) 'p_after': feedAfter,
        if (feedCursor != null) 'p_cursor': feedCursor,
      }) as Map;
      if (!mounted) return;
      feedAfter = result['after'] as String;
      feedCursor = result['cursor'] as String;
      for (final item in result['items'] as List) {
        final event = Map<String, dynamic>.from(item as Map);
        if (seenGifts.add(
          '${event['is_test'] == true ? 'test:' : 'real:'}${event['id']}',
        ))
          widget.onGift?.call(comboFeed.add(event));
      }
      if (seenGifts.length > 1000)
        seenGifts.removeAll(seenGifts.take(seenGifts.length - 1000).toList());
    } catch (_) {
      /* Keep the last cursor and retry without replaying gifts. */
    } finally {
      readingFeed = false;
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final result = await Future.wait([
        widget.repo.rpc('live_gifts', {
          'p_action': 'info',
          'p_session': widget.session,
        }),
        widget.repo.rpc('live_battle', {
          'p_action': 'info',
          'p_session': widget.session,
        }),
        widget.repo.rpc('live_party', {
          'p_action': 'info',
          'p_session': widget.session,
        }),
        widget.repo.rpc('test_wallet', {}),
      ]);
      if (mounted)
        setState(() {
          gifts = Map<String, dynamic>.from(result[0] as Map);
          battle = Map<String, dynamic>.from(result[1] as Map);
          party = Map<String, dynamic>.from(result[2] as Map);
          testCoins = ((result[3] as Map)['coins'] as num).toInt();
          widget.onBattle?.call(battle);
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      loading = false;
    }
  }

  Future<void> act(String action, {String? opponent}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.repo.rpc('live_battle', {
        'p_action': action,
        'p_session': widget.session,
        if (opponent != null) 'p_opponent': opponent,
      });
      await load();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendPending() async {
    final intent = pendingGift;
    if (intent == null || busy) return;
    setState(() => busy = true);
    try {
      if (pendingTest) {
        final testIntent = Map<String, dynamic>.from(intent)
          ..remove('p_action');
        await widget.repo.rpc('test_live_gift', testIntent);
      } else {
        await widget.repo.rpc('live_gifts', intent);
      }
      await readFeed();
      if (mounted)
        setState(() {
          pendingGift = null;
          comboCount++;
          comboUntil = DateTime.now().add(const Duration(seconds: 12));
          error = null;
        });
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = socialError(e));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${error!} Open LIVE menu → Gifts to retry the same gift.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseGift({bool test = false}) async {
    if (choosing || busy || pendingGift != null || feedCursor == null) return;
    setState(() => choosing = true);
    try {
      await chooseGiftFlow(test: test);
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> chooseGiftFlow({bool test = false}) async {
    if (busy || pendingGift != null || feedCursor == null) return;
    var recipient = hostId;
    if (recipient == null) return;
    if (!test && recipient == widget.repo.uid) {
      final others = people.where(
        (p) => test || p['user_id'] != widget.repo.uid,
      );
      if (others.isEmpty) {
        setState(
          () =>
              error = 'You cannot gift yourself. Add an approved guest first.',
        );
        return;
      }
      recipient = others.first['user_id'] as String;
    }
    int? balance;
    try {
      final wallet = await widget.repo
          .rpc('wallet', {})
          .timeout(const Duration(seconds: 8));
      balance = test ? testCoins : (wallet['coins'] as num?)?.toInt();
    } catch (_) {
      balance = test ? testCoins : null;
    }
    if (!mounted) return;
    final recipients = people
        .where((p) => test || p['user_id'] != widget.repo.uid)
        .toList();
    final choice = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => PulseGiftGallery(
        gifts: (gifts['gifts'] as List? ?? []).cast<Map>(),
        people: recipients,
        recipient: recipient!,
        test: test,
        balance: balance,
        onChoose: (gift) => Navigator.pop(sheet, gift),
        onRecharge: () => Navigator.push(
          sheet,
          MaterialPageRoute<void>(
            builder: (_) => PulseShopPage(repo: widget.repo),
          ),
        ),
        onPreview: (gift) => Navigator.push(
          sheet,
          MaterialPageRoute<void>(
            builder: (preview) => Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: PulseLiveGiftPresentation(
                      repo: widget.repo,
                      event: {
                        ...gift,
                        'quantity': 1,
                        'display_name': 'Preview',
                        'preview_only': true,
                        'is_test': true,
                      },
                      sound: true,
                      onComplete: () {
                        if (preview.mounted &&
                            ModalRoute.of(preview)?.isCurrent == true)
                          Navigator.pop(preview);
                      },
                    ),
                  ),
                  SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close preview',
                          onPressed: () => Navigator.pop(preview),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        const Text(
                          'PREVIEW · no coins spent',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await sendOne(choice, test: test);
  }

  Future<void> sendOne(Map choice, {required bool test}) async {
    if (busy || pendingGift != null) return;
    if (comboGift?['sku'] != choice['sku'] ||
        comboGift?['recipient'] != choice['recipient'] ||
        comboTest != test ||
        !showCombo)
      comboCount = 0;
    comboGift = Map.from(choice);
    comboTest = test;
    pendingTest = test;
    setState(
      () => pendingGift = {
        'p_action': 'send',
        'p_session': widget.session,
        'p_recipient': choice['recipient'],
        'p_sku': choice['sku'],
        'p_quantity': 1,
        'p_id': const Uuid().v4(),
      },
    );
    await sendPending();
  }

  Future<void> invite() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Invite an approved guest to battle')),
            for (final p in people.where((p) => p['user_id'] != hostId))
              ListTile(
                title: Text('${p['display_name']}'),
                onTap: () => Navigator.pop(sheet, p['user_id'] as String),
              ),
            if (people.length < 2)
              const ListTile(title: Text('Approve a guest on stage first.')),
          ],
        ),
      ),
    );
    if (choice != null) await act('invite', opponent: choice);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> showControls(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .65,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<int>(
            stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
            builder: (_, __) => controls(sheet),
          ),
        ),
      ),
    ),
  );

  Widget comboButton() => Tooltip(
    message:
        'Send one more ${comboGift?['title']} for ${comboGift?['coins']} ${comboTest ? 'test' : 'normal'} coins',
    child: FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      ),
      onPressed: busy || pendingGift != null || choosing
          ? null
          : () => sendOne(comboGift!, test: comboTest),
      child: Text(
        '+1 · ${comboGift?['coins']} coins\nCombo ×${comboCount + (busy && pendingGift != null ? 1 : 0)}${busy && pendingGift != null ? ' · sending' : ''}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.compact
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Send gift',
              onPressed:
                  busy || choosing || pendingGift != null || feedCursor == null
                  ? null
                  : () => chooseGift(),
              icon: const Icon(Icons.card_giftcard, color: Color(0xffff4e91)),
            ),
            if (showCombo) comboButton(),
          ],
        )
      : controls(context);

  Widget controls(BuildContext context) {
    final active = battle['state'] == 'active';
    final invited = battle['state'] == 'invited';
    final opponent = battle['opponent_id'] == widget.repo.uid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active || invited || battle['state'] == 'ended')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              invited
                  ? 'Battle invitation · waiting for acceptance'
                  : active
                  ? 'BATTLE · ${battle['remaining']}s · ${battle['host_score']} vs ${battle['opponent_score']}'
                  : 'Battle ended · ${battle['host_score']} vs ${battle['opponent_score']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showCombo) comboButton(),
            TextButton.icon(
              onPressed:
                  busy || choosing || pendingGift != null || feedCursor == null
                  ? null
                  : () => chooseGift(),
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Gift'),
            ),
            if (testCoins > 0)
              TextButton.icon(
                onPressed:
                    busy ||
                        choosing ||
                        pendingGift != null ||
                        feedCursor == null
                    ? null
                    : () => chooseGift(test: true),
                icon: const Icon(Icons.science_outlined),
                label: Text('Test gifts · $testCoins'),
              ),
            IconButton(
              tooltip: 'Shop & wallet',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PulseShopPage(repo: widget.repo),
                ),
              ),
              icon: const Icon(Icons.storefront_outlined),
            ),
            if (widget.host && !active && !invited)
              TextButton.icon(
                onPressed: busy ? null : invite,
                icon: const Icon(Icons.bolt),
                label: const Text('Battle'),
              ),
            if (invited && opponent) ...[
              TextButton(
                onPressed: busy ? null : () => act('accept'),
                child: const Text('Accept battle'),
              ),
              TextButton(
                onPressed: busy ? null : () => act('decline'),
                child: const Text('Decline'),
              ),
            ],
            if (active && (widget.host || opponent))
              TextButton(
                onPressed: busy ? null : () => act('end'),
                child: const Text('End battle'),
              ),
            if (pendingGift != null) ...[
              TextButton(
                onPressed: busy ? null : sendPending,
                child: const Text('Retry same gift'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() => pendingGift = null);
                      },
                child: const Text('Dismiss'),
              ),
            ],
          ],
        ),
        if ((gifts['recent'] as List? ?? []).isNotEmpty)
          Text(
            '${gifts['recent'][0]['display_name']} sent ${gifts['recent'][0]['sku']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (error != null)
          Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
