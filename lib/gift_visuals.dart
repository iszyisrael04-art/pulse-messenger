import 'legendary_catalog.dart';

import 'package:flutter/material.dart';

import 'gift_assets.dart';

/// Static thumbnails and flat icons. No meshes, shaders, filters or particles.
class PulseGiftModel extends StatelessWidget {
  const PulseGiftModel({super.key, required this.sku});
  final String sku;
  @override
  Widget build(BuildContext context) {
    const smallGiftArt = <String, String>{
      'rose': 'assets/gifts/gift_rose.webp',
      'heart': 'assets/gifts/gift_heart.webp',
      'coffee': 'assets/gifts/gift_coffee.webp',
      'pearl': 'assets/gifts/gift_pearl.webp',
      'star': 'assets/gifts/gift_star.webp',
      'butterfly': 'assets/gifts/gift_butterfly.webp',
      'fire': 'assets/gifts/gift_fire.webp',
      'fireworks': 'assets/gifts/gift_fireworks.webp',
      'crown': 'assets/gifts/gift_crown.webp',
      'trophy': 'assets/gifts/gift_trophy.webp',
    };
    final smallArt = smallGiftArt[sku];
    if (smallArt != null) {
      return Image.asset(
        smallArt,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard),
      );
    }
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
  final String giftSku;
  @override
  Widget build(BuildContext context) {
    final legendary = pulseLegendaryGifts.containsKey(giftSku);
    final premium = pulsePremiumGifts.containsKey(giftSku);
    final nameStyle = TextStyle(
      color: legendary
          ? const Color(0xffffd44f)
          : premium
          ? const Color(0xffd88bff)
          : Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 13,
      shadows: legendary
          ? const [
              Shadow(color: Color(0xffffc52f), blurRadius: 9),
              Shadow(color: Color(0xfffff3ad), blurRadius: 16),
            ]
          : premium
          ? const [Shadow(color: Color(0xffb84dff), blurRadius: 12)]
          : null,
    );
    return Align(
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
                  style: nameStyle,
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
}
