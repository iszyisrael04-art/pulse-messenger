import 'package:flutter/material.dart';

/// Original Pulse mark; no third-party logo or proprietary assets.
class PulseMark extends StatelessWidget {
  const PulseMark({super.key, this.size = 36, this.color, this.tile = false});
  final double size;
  final Color? color;
  final bool tile;
  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.primary;
    final mark = CustomPaint(
      size: Size.square(size),
      painter: PulseMarkPainter(tile ? Colors.white : ink),
    );
    return Semantics(
      label: 'Pulse',
      image: true,
      child: tile
          ? Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(size * .18),
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(size * .25),
              ),
              child: mark,
            )
          : SizedBox.square(dimension: size, child: mark),
    );
  }
}

class PulseMarkPainter extends CustomPainter {
  PulseMarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(15, 52)
      ..lineTo(32, 52)
      ..lineTo(42, 26)
      ..lineTo(58, 75)
      ..lineTo(70, 46)
      ..lineTo(86, 46);
    canvas.drawPath(path, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PulseMarkPainter old) => old.color != color;
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
  });
  final int selected;
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
                            Icon(
                              selected == i ? active[i] : icons[i],
                              size: 24,
                              color: selected == i
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
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
