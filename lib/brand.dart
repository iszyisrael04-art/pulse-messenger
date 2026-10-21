import 'package:flutter/material.dart';

/// Original Pulse mark; no third-party logo or proprietary assets.
class PulseMark extends StatelessWidget {
  const PulseMark({super.key, this.size = 36, this.color, this.tile = false});
  final double size;
  final Color? color;
  final bool tile;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pulse',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * (tile ? .25 : .20)),
        child: Image.asset(
          'assets/branding/pulse.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class PulseWordmark extends StatelessWidget {
  const PulseWordmark({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    'pulse',
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -size * .045,
      color: color,
    ),
  );
}

class PulseBottomNav extends StatelessWidget {
  const PulseBottomNav({
    super.key,
    required this.selected,
    required this.onSelect,
    this.unread = 0,
    this.profileImage,
  });
  final int selected, unread;
  final Widget? profileImage;
  final ValueChanged<int> onSelect;
  static const labels = [
    'Home',
    'Reels',
    'Create',
    'Chats',
    'Groups',
    'Profile',
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.smart_display_outlined,
    Icons.add,
    Icons.chat_bubble_outline_rounded,
    Icons.groups_outlined,
    Icons.person_outline_rounded,
  ];
  static const active = [
    Icons.home_rounded,
    Icons.smart_display_rounded,
    Icons.add,
    Icons.chat_bubble_rounded,
    Icons.groups_rounded,
    Icons.person_rounded,
  ];
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 6; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    label: labels[i],
                    button: true,
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (i == 2)
                            Container(
                              width: 38,
                              height: 30,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                color: cs.onPrimary,
                                size: 24,
                              ),
                            )
                          else
                            Badge(
                              isLabelVisible: i == 3 && unread > 0,
                              label: Text(unread > 99 ? '99+' : '$unread'),
                              child: i == 5 && profileImage != null
                                  ? profileImage!
                                  : Icon(
                                      selected == i ? active[i] : icons[i],
                                      size: 24,
                                      color: selected == i
                                          ? cs.onSurface
                                          : cs.onSurfaceVariant,
                                    ),
                            ),
                          const SizedBox(height: 5),
                          Text(
                            labels[i],
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected == i
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedPulseFavicon extends StatefulWidget {
  const AnimatedPulseFavicon({super.key, this.size = 88});
  final double size;
  @override
  State<AnimatedPulseFavicon> createState() => _AnimatedPulseFaviconState();
}

class _AnimatedPulseFaviconState extends State<AnimatedPulseFavicon>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
      motion.value = .5;
    } else if (!motion.isAnimating)
      motion.repeat(reverse: true);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (_, __) => Transform.scale(
      scale: .96 + .04 * Curves.easeInOut.transform(motion.value),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size * .25),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xff23e5ba,
              ).withValues(alpha: .10 + motion.value * .12),
              blurRadius: 18 + motion.value * 14,
              spreadRadius: motion.value * 3,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * .25),
          child: Image.asset(
            'assets/branding/pulse.png',
            width: widget.size,
            height: widget.size,
          ),
        ),
      ),
    ),
  );
}
