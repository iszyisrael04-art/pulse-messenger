import 'gift_visuals.dart';
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
  });
  final PulseRepository repo;
  final String session;
  final bool host;
  final ValueChanged<Map<String, dynamic>>? onGift;
  @override
  State<PulseLiveGifts> createState() => _PulseLiveGiftsState();
}

class _PulseLiveGiftsState extends State<PulseLiveGifts> {
  Map<String, dynamic> gifts = {}, battle = {}, party = {};
  Timer? timer;
  bool loading = false, busy = false;
  String? error, feedAfter, feedCursor;
  bool readingFeed = false, pendingTest = false;
  int testCoins = 0;
  final seenGifts = <String>{};
  Map<String, dynamic>? pendingGift;
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
      final result =
          await widget.repo.rpc('gift_feed', {
                'p_session': widget.session,
                if (feedAfter != null) 'p_after': feedAfter,
                if (feedCursor != null) 'p_cursor': feedCursor,
              })
              as Map;
      if (!mounted) return;
      feedAfter = result['after'] as String;
      feedCursor = result['cursor'] as String;
      for (final item in result['items'] as List) {
        final event = Map<String, dynamic>.from(item as Map);
        if (seenGifts.add(
          '${event['is_test'] == true ? 'test:' : 'real:'}${event['id']}',
        ))
          widget.onGift?.call(event);
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
          error = null;
        });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseGift({bool test = false}) async {
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
    final choice = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .65,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  test ? 'Send a TEST gift' : 'Send a LIVE gift',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                DropdownButtonFormField<String>(
                  initialValue: recipient,
                  items: people
                      .where((p) => p['user_id'] != widget.repo.uid)
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['user_id'] as String,
                          child: Text('${p['display_name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => update(() => recipient = v),
                ),
                Text(
                  test
                      ? 'Test coins only. No P-coins, cash value or rank progress.'
                      : 'Normal coins are spent. The recipient earns the listed P-coins.',
                ),
                for (final gift in gifts['gifts'] as List? ?? [])
                  ListTile(
                    leading: SizedBox(
                      width: 52,
                      height: 52,
                      child: PulseGiftModel(sku: gift['sku']),
                    ),
                    title: Text('${gift['title']} · ${gift['coins']} coins'),
                    subtitle: Text(
                      test
                          ? 'Test animation · no earnings'
                          : 'Recipient gets ${gift['p_coins']} P-coins',
                    ),
                    onTap: () => Navigator.pop(sheet, {
                      'sku': gift['sku'],
                      'recipient': recipient,
                      'title': gift['title'],
                      'coins': gift['coins'],
                      'p_coins': gift['p_coins'],
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final quantityInput = TextEditingController(text: '1');
    final amountForm = GlobalKey<FormState>();
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('How many ${choice['title']} gifts?'),
        content: Form(
          key: amountForm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 120,
                width: 160,
                child: PulseGiftModel(sku: choice['sku']),
              ),
              TextFormField(
                controller: quantityInput,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Quantity · 1–100',
                ),
                validator: (v) {
                  final q = int.tryParse(v ?? '');
                  return q == null || q < 1 || q > 100 ? 'Enter 1–100' : null;
                },
              ),
              ValueListenableBuilder(
                valueListenable: quantityInput,
                builder: (_, value, __) {
                  final q = int.tryParse(value.text) ?? 0;
                  return Text(
                    test
                        ? 'Total: ${q * (choice['coins'] as num)} test coins\nNo P-coins or rank credit'
                        : 'Total: ${q * (choice['coins'] as num)} normal coins\nRecipient: ${q * (choice['p_coins'] as num)} P-coins',
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (amountForm.currentState!.validate())
                Navigator.pop(dialog, int.parse(quantityInput.text));
            },
            child: Text(test ? 'Send TEST gifts' : 'Send gifts'),
          ),
        ],
      ),
    );
    // Dispose after the dialog exit animation has detached its text field.
    Future<void>.delayed(const Duration(seconds: 1), quantityInput.dispose);
    if (quantity == null || !mounted) return;
    pendingTest = test;
    setState(
      () => pendingGift = {
        'p_action': 'send',
        'p_session': widget.session,
        'p_recipient': choice['recipient'],
        'p_sku': choice['sku'],
        'p_quantity': quantity,
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

  @override
  Widget build(BuildContext context) {
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
            TextButton.icon(
              onPressed: busy || pendingGift != null || feedCursor == null
                  ? null
                  : () => chooseGift(),
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Gift'),
            ),
            if (testCoins > 0)
              TextButton.icon(
                onPressed: busy || pendingGift != null || feedCursor == null
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
