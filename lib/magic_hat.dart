import 'dart:math' as math;
import 'package:flutter/material.dart';

class PulseMagicHat extends StatefulWidget {
  const PulseMagicHat({super.key, required this.sku});
  final String sku;
  @override
  State<PulseMagicHat> createState() => _PulseMagicHatState();
}
class _PulseMagicHatState extends State<PulseMagicHat> with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { motion.stop(); } else { motion.repeat(); }
  }
  @override
  void dispose() { motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (_, __) => Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _SpellAura(motion.value, widget.sku == 'witch_filter')),
        Image.asset('assets/gifts/filter_${widget.sku == 'witch_filter' ? 'witch_hat' : 'wizard_hat'}.webp', fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      ],
    ),
  );
}
class _SpellAura extends CustomPainter {
  _SpellAura(this.phase, this.witch);
  final double phase;
  final bool witch;
  @override
  void paint(Canvas canvas, Size size) {
    final color = witch ? const Color(0xffb789ed) : const Color(0xff77caff);
    final center = Offset(size.width * .5, size.height * .65);
    final glow = Paint()..color = color.withValues(alpha: .20)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(Rect.fromCenter(center: center, width: size.width * .85, height: size.height * .32), glow);
    for (var i = 0; i < 14; i++) {
      final a = (phase + i / 14) * math.pi * 2;
      final p = center + Offset(math.cos(a) * size.width * .44, math.sin(a) * size.height * .24);
      canvas.drawCircle(p, 1.1 + i % 3 * .5, Paint()..color = color.withValues(alpha: .65));
    }
  }
  @override
  bool shouldRepaint(covariant _SpellAura old) => old.phase != phase || old.witch != witch;
}
