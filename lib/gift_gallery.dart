import 'dart:async';
import 'dart:ui' as ui;

import 'legendary_overlay.dart';
import 'legendary_catalog.dart';
import 'gift_assets.dart';

import 'package:flutter/material.dart';

import 'gift_visuals.dart';
import 'pulse_coin.dart';

String pulseGiftTitle(String sku, String title) =>
    sku == 'galaxy' ? 'Pulse Universe' : title;

/// Selection and preview never spend coins. Send submits one gift immediately.
class PulseGiftGallery extends StatefulWidget {
  const PulseGiftGallery({
    super.key,
    required this.gifts,
    required this.people,
    required this.recipient,
    required this.onChoose,
    required this.onPreview,
    required this.onRecharge,
    required this.test,
    this.balance,
  });
  final List<Map> gifts, people;
  final String recipient;
  final ValueChanged<Map> onChoose;
  final ValueChanged<Map> onPreview;
  final VoidCallback onRecharge;
  final bool test;
  final int? balance;
  @override
  State<PulseGiftGallery> createState() => _PulseGiftGalleryState();
}

class _PulseGiftGalleryState extends State<PulseGiftGallery> {
  late String recipient = widget.recipient;
  String tab = 'All';
  Map? selected;
  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported &&
        widget.gifts.any((g) => g['sku'] == 'legend_lion_king')) {
      unawaited(() async {
        try {
          await PulseLegendaryBytes.load('legend_lion_king');
        } catch (_) {}
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.gifts
        .where(
          (g) =>
              tab == 'All' ||
              (tab == 'Legendary'
                  ? pulseLegendaryGifts.containsKey(g['sku'])
                  : tab == 'Videos'
                  ? pulseGiftHasVideo(g)
                  : !pulseGiftHasVideo(g)),
        )
        .toList();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.test ? 'Gift studio · TEST' : 'Send a gift',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close gifts',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (widget.people.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: recipient,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Send to',
                isDense: true,
              ),
              items: widget.people
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p['user_id'] as String,
                      child: Text(
                        '${p['display_name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => recipient = v);
              },
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final value in [
                'All',
                'Legendary',
                'Videos',
                'Notifications',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: tab == value,
                    onSelected: (_) => setState(() => tab = value),
                  ),
                ),
              const Text('Tap gift = send 1', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = (bounds.maxWidth / (scale > 1.4 ? 150 : 90))
                  .floor()
                  .clamp(2, 6);
              return GridView.builder(
                key: ValueKey(tab),
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: scale > 1.4 ? 210 : 166,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final gift = items[i], sku = gift['sku'] as String;
                  final active = selected?['sku'] == sku;
                  return Semantics(
                    selected: active,
                    button: true,
                    label:
                        '${pulseGiftTitle(sku, gift['title'])}, ${gift['coins']} coins',
                    child: InkWell(
                      onTap: () => widget.onChoose({
                        ...gift,
                        'title': pulseGiftTitle(sku, gift['title']),
                        'recipient': recipient,
                      }),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0x2281d5c2)
                              : Colors.white.withValues(alpha: .03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active
                                ? const Color(0xff81d5c2)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(child: PulseGiftModel(sku: sku)),
                            Text(
                              pulseGiftTitle(sku, gift['title']),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const PulseCoin(),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${gift['coins']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              tooltip:
                                  'Preview ${pulseGiftTitle(sku, gift['title'])}',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() => selected = gift);
                                widget.onPreview(gift);
                              },
                              icon: const Icon(
                                Icons.play_circle_outline,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.test
                            ? 'No cash value or rank credit'
                            : 'Recipient: ${selected!['p_coins']} P-coins per gift',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => widget.onPreview(selected!),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Preview'),
                    ),
                  ],
                ),
              Row(
                children: [
                  const PulseCoin(),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      widget.balance == null ? 'Wallet' : '${widget.balance}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!widget.test &&
                      MediaQuery.textScalerOf(context).scale(1) > 1.4)
                    IconButton(
                      tooltip: 'Recharge',
                      onPressed: widget.onRecharge,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  if (!widget.test &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.4)
                    TextButton(
                      onPressed: widget.onRecharge,
                      child: const Text('Recharge'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final short = MediaQuery.sizeOf(context).height < 480;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * (short ? .94 : .74),
        child: short
            ? SingleChildScrollView(
                child: SizedBox(height: 650, child: content),
              )
            : content,
      ),
    );
  }
}
