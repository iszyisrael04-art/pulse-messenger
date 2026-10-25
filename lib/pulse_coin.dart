import 'package:flutter/material.dart';

/// Original Pulse currency mark. Keep the artwork tiny; the price stays legible.
class PulseCoin extends StatelessWidget {
  const PulseCoin({super.key, this.size = 12});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'coins',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _CoinPainter()),
    ),
  );
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final c = r.center;
    canvas.drawCircle(
      c,
      size.width / 2,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffffefb0), Color(0xffffc83d), Color(0xffb8780c)],
        ).createShader(r),
    );
    canvas.drawCircle(
      c,
      size.width * .37,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .065
        ..color = const Color(0xffad700d),
    );
    final path = Path()
      ..moveTo(size.width * .40, size.height * .73)
      ..lineTo(size.width * .40, size.height * .29)
      ..lineTo(size.width * .57, size.height * .29)
      ..cubicTo(
        size.width * .79,
        size.height * .29,
        size.width * .79,
        size.height * .55,
        size.width * .57,
        size.height * .55,
      )
      ..lineTo(size.width * .41, size.height * .55);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .085
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xff85520b),
    );
  }

  @override
  bool shouldRepaint(covariant _CoinPainter oldDelegate) => false;
}
