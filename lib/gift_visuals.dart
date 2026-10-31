import 'legendary_catalog.dart';

import 'package:flutter/material.dart';

import 'gift_assets.dart';

/// Static thumbnails and flat icons. No meshes, shaders, filters or particles.
class PulseGiftModel extends StatelessWidget {
  const PulseGiftModel({super.key, required this.sku});
  final String sku;
  @override
  Widget build(BuildContext context) {
    if (pulseGiftMovies.containsKey(sku) ||
        pulseCinematicGifts.containsKey(sku)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/gifts/thumb_${pulseGiftMovies[sku] ?? sku}.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard),
        ),
      );
    }
    final icon = switch (sku) {
      'rose' => Icons.local_florist,
      'heart' => Icons.favorite,
      'coffee' => Icons.local_cafe,
      'star' => Icons.star,
      'fire' => Icons.local_fire_department,
      'butterfly' => Icons.flutter_dash,
      'diamond' => Icons.diamond,
      'crown' => Icons.workspace_premium,
      'rocket' => Icons.rocket_launch,
      'trophy' => Icons.emoji_events,
      'castle' => Icons.castle,
      'saturn' => Icons.public,
      'pearl' => Icons.circle,
      'fireworks' => Icons.celebration,
      _ => Icons.card_giftcard,
    };
    return FittedBox(
      child: Icon(
        icon,
        size: 48,
        color: sku == 'heart' || sku == 'rose'
            ? Colors.pinkAccent
            : const Color(0xff81d5c2),
      ),
    );
  }
}

/// Plain LIVE notification in the marked left-hand area above chat.
class PulseGiftNotice extends StatelessWidget {
  const PulseGiftNotice({
    super.key,
    required this.name,
    required this.title,
    required this.quantity,
    required this.avatar,
    required this.gift,
    this.test = false,
    this.coins,
    this.alignment = const Alignment(-1, .1),
  });
  final String name, title;
  final int? coins;
  final Alignment alignment;
  final int quantity;
  final Widget avatar, gift;
  final bool test;
  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.only(left: 12, right: 42),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xcc17232a),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 38, height: 38, child: avatar),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${test ? 'TEST · ' : ''}$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Sent $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (coins != null)
                  Text(
                    '${coins.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")} Coins',
                    style: const TextStyle(
                      color: Color(0xffffd680),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 44, height: 44, child: gift),
          const SizedBox(width: 5),
          Text(
            '×$quantity',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    ),
  );
}
