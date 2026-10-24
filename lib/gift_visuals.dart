import 'gifter_ranks.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'avatar.dart';
import 'repository.dart' hide Row;

// Real perspective-projected triangle meshes, shaded and depth sorted locally.
// No emoji, WebView, downloaded video, or paid 3D runtime is used for gifts.
class GiftVertex {
  const GiftVertex(this.x, this.y, this.z);
  final double x, y, z;
}

class GiftFace {
  const GiftFace(this.a, this.b, this.c, this.color);
  final GiftVertex a, b, c;
  final Color color;
}

class GiftMesh {
  final faces = <GiftFace>[];
  void triangle(GiftVertex a, GiftVertex b, GiftVertex c, Color color) =>
      faces.add(GiftFace(a, b, c, color));
  void sphere(
    double x,
    double y,
    double z,
    double rx,
    double ry,
    double rz,
    Color color, {
    int segments = 12,
    int rings = 8,
  }) {
    GiftVertex v(int i, int j) {
      final a = i * math.pi / rings, b = j * 2 * math.pi / segments;
      return GiftVertex(
        x + rx * math.sin(a) * math.cos(b),
        y + ry * math.cos(a),
        z + rz * math.sin(a) * math.sin(b),
      );
    }

    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < segments; j++) {
        triangle(v(i, j), v(i + 1, j), v(i + 1, j + 1), color);
        triangle(v(i, j), v(i + 1, j + 1), v(i, j + 1), color);
      }
    }
  }

  void cone(
    double x,
    double y,
    double z,
    double radius,
    double height,
    Color color, {
    double top = 0,
    int segments = 16,
  }) {
    for (var i = 0; i < segments; i++) {
      final a = i * 2 * math.pi / segments,
          b = (i + 1) * 2 * math.pi / segments;
      final p = GiftVertex(
        x + radius * math.cos(a),
        y,
        z + radius * math.sin(a),
      );
      final q = GiftVertex(
        x + radius * math.cos(b),
        y,
        z + radius * math.sin(b),
      );
      final r = GiftVertex(
        x + top * math.cos(a),
        y + height,
        z + top * math.sin(a),
      );
      final s = GiftVertex(
        x + top * math.cos(b),
        y + height,
        z + top * math.sin(b),
      );
      triangle(p, q, r, color);
      triangle(q, s, r, color);
      triangle(GiftVertex(x, y, z), q, p, color);
    }
  }

  void gem(
    double x,
    double y,
    double z,
    double radius,
    Color color, {
    double tall = 1.2,
    int sides = 8,
  }) {
    for (var i = 0; i < sides; i++) {
      final a = i * 2 * math.pi / sides, b = (i + 1) * 2 * math.pi / sides;
      final p = GiftVertex(
        x + radius * math.cos(a),
        y,
        z + radius * math.sin(a),
      );
      final q = GiftVertex(
        x + radius * math.cos(b),
        y,
        z + radius * math.sin(b),
      );
      triangle(p, q, GiftVertex(x, y + radius * tall, z), color);
      triangle(q, p, GiftVertex(x, y - radius * tall, z), color);
    }
  }

  static final _cache = <String, GiftMesh>{};
  static GiftMesh forSku(String sku) => _cache.putIfAbsent(sku, () {
    final m = GiftMesh();
    const gold = Color(0xffffca51),
        pink = Color(0xffff387e),
        cyan = Color(0xff58e8ff);
    switch (sku) {
      case 'rose':
        m.cone(0, -1.2, 0, .045, 1.3, const Color(0xff2eab65), top: .04);
        m.sphere(-.25, -.65, 0, .32, .12, .08, const Color(0xff38b879));
        for (var i = 0; i < 9; i++) {
          final a = i * 2 * math.pi / 9;
          m.sphere(
            .28 * math.cos(a),
            .25 + .08 * (i % 2),
            .28 * math.sin(a),
            .25,
            .43,
            .16,
            Color.lerp(pink, const Color(0xffffa3b8), i / 15)!,
          );
        }
        m.sphere(0, .45, 0, .23, .35, .23, pink);
      case 'heart':
        m.sphere(-.3, .25, 0, .48, .48, .3, pink);
        m.sphere(.3, .25, 0, .48, .48, .3, pink);
        m.cone(0, -.85, 0, 0, 1.15, pink, top: .65);
      case 'coffee':
        m.cone(0, -.6, 0, .45, 1.05, const Color(0xfff0e3d1), top: .6);
        m.sphere(0, .44, 0, .53, .035, .53, const Color(0xff542a1c));
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 7;
          m.sphere(
            .57 + .23 * math.sin(a),
            -.1 + .38 * math.cos(a),
            0,
            .1,
            .1,
            .12,
            gold,
            segments: 8,
            rings: 5,
          );
        }
        for (var i = 0; i < 3; i++) {
          m.sphere(
            (i - 1) * .22,
            .75 + i * .13,
            0,
            .06,
            .22,
            .06,
            const Color(0xffc9ecff),
            segments: 8,
            rings: 5,
          );
        }
      case 'star':
        for (var i = 0; i < 10; i++) {
          GiftVertex rim(int j, double z) {
            final angle = j * math.pi / 5, r = j.isEven ? .95 : .43;
            return GiftVertex(math.sin(angle) * r, math.cos(angle) * r, z);
          }

          m.triangle(
            const GiftVertex(0, 0, .28),
            rim(i, .1),
            rim(i + 1, .1),
            gold,
          );
          m.triangle(
            const GiftVertex(0, 0, -.28),
            rim(i + 1, -.1),
            rim(i, -.1),
            gold,
          );
          m.triangle(rim(i, .1), rim(i, -.1), rim(i + 1, .1), gold);
          m.triangle(rim(i + 1, .1), rim(i, -.1), rim(i + 1, -.1), gold);
        }
      case 'fire':
        for (var layer = 0; layer < 2; layer++) {
          GiftVertex flame(int ring, int segment) {
            final t = ring / 10, a = segment * 2 * math.pi / 18;
            final radius =
                math.sin(math.pow(1 - t, .7) * math.pi) * (.55 - layer * .2);
            return GiftVertex(
              .2 * math.sin(t * math.pi * 2) + radius * math.cos(a),
              -.8 + t * (1.9 - layer * .5),
              radius * math.sin(a) + layer * .22,
            );
          }

          for (var ring = 0; ring < 10; ring++) {
            for (var j = 0; j < 18; j++) {
              final color = layer == 0 ? const Color(0xffff6424) : gold;
              m.triangle(
                flame(ring, j),
                flame(ring + 1, j),
                flame(ring + 1, j + 1),
                color,
              );
              m.triangle(
                flame(ring, j),
                flame(ring + 1, j + 1),
                flame(ring, j + 1),
                color,
              );
            }
          }
        }
      case 'crown':
        m.cone(0, -.55, 0, .7, .45, gold, top: .7);
        for (var i = 0; i < 7; i++) {
          final a = i * 2 * math.pi / 7;
          m.cone(.58 * math.cos(a), -.2, .58 * math.sin(a), .16, .7, gold);
          m.gem(.58 * math.cos(a), .55, .58 * math.sin(a), .12, pink);
        }
      case 'diamond':
        m.gem(0, 0, 0, .85, cyan, tall: 1.15);
        m.gem(0, .05, .08, .42, const Color(0xffe8fbff), tall: 1.6);
      case 'rocket':
        m.cone(0, -.65, 0, .32, 1.35, const Color(0xffdceaff), top: .32);
        m.cone(0, .7, 0, .32, .55, pink);
        m.sphere(0, .25, .31, .18, .18, .05, cyan);
        for (var i = 0; i < 3; i++) {
          final a = i * 2 * math.pi / 3;
          m.gem(
            .34 * math.cos(a),
            -.65,
            .34 * math.sin(a),
            .21,
            pink,
            tall: 1.7,
            sides: 4,
          );
        }
        m.cone(0, -1.3, 0, .02, .65, gold, top: .23);
      case 'galaxy':
        m.sphere(0, 0, 0, .48, .48, .48, const Color(0xff9564ff));
        for (var i = 0; i < 24; i++) {
          final a = i * 2 * math.pi / 24;
          m.gem(
            .92 * math.cos(a),
            .2 * math.sin(a),
            .75 * math.sin(a),
            .09,
            Color.lerp(cyan, pink, i / 24)!,
          );
        }
        m.gem(.7, .8, 0, .15, gold);
        m.gem(-.9, -.6, 0, .12, cyan);
      case 'lion':
        for (var i = 0; i < 12; i++) {
          final a = i * 2 * math.pi / 12;
          m.gem(
            .65 * math.sin(a),
            .65 * math.cos(a),
            -.1,
            .31,
            const Color(0xffb86917),
            tall: 1.4,
          );
        }
        m.sphere(0, 0, 0, .65, .67, .48, gold);
        m.sphere(-.43, .47, 0, .21, .22, .14, gold);
        m.sphere(.43, .47, 0, .21, .22, .14, gold);
        m.sphere(-.25, .15, .45, .09, .12, .06, const Color(0xff14233d));
        m.sphere(.25, .15, .45, .09, .12, .06, const Color(0xff14233d));
        m.sphere(0, -.28, .44, .38, .26, .22, const Color(0xffffe5a7));
        m.gem(0, -.13, .66, .12, const Color(0xff332839), tall: .7, sides: 4);
        m.sphere(0, -.43, .62, .15, .09, .035, const Color(0xff53293b));
      default:
        m.gem(0, 0, 0, .8, cyan);
    }
    return m;
  });
}

class PulseGiftModel extends StatelessWidget {
  const PulseGiftModel({super.key, required this.sku, this.phase = 0});
  final String sku;
  final double phase;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _GiftPainter(sku, phase), size: Size.infinite),
  );
}

class _GiftPainter extends CustomPainter {
  _GiftPainter(this.sku, this.phase);
  final String sku;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final angle = math.sin(phase * math.pi * 2) * .45 + .3,
        ca = math.cos(angle),
        sa = math.sin(angle);
    GiftVertex turn(GiftVertex p) => GiftVertex(
      p.x * ca + p.z * sa,
      p.y * .98 + (p.z * ca - p.x * sa) * .2,
      (p.z * ca - p.x * sa) * .98 - p.y * .2,
    );
    Offset project(GiftVertex p) {
      final f = 4 / (4 - p.z);
      return Offset(
        size.width / 2 + p.x * f * size.shortestSide * .3,
        size.height / 2 - p.y * f * size.shortestSide * .3,
      );
    }

    final faces =
        GiftMesh.forSku(sku).faces
            .map((f) => (turn(f.a), turn(f.b), turn(f.c), f.color))
            .toList()
          ..sort(
            (a, b) => ((a.$1.z + a.$2.z + a.$3.z) - (b.$1.z + b.$2.z + b.$3.z))
                .sign
                .toInt(),
          );
    final paint = Paint()..isAntiAlias = true;
    for (final f in faces) {
      final ux = f.$2.x - f.$1.x, uy = f.$2.y - f.$1.y, uz = f.$2.z - f.$1.z;
      final vx = f.$3.x - f.$1.x, vy = f.$3.y - f.$1.y, vz = f.$3.z - f.$1.z;
      final nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      final light = length == 0
          ? .65
          : (.55 + .45 * ((nx * .3 + ny * .6 + nz * .7) / length).abs()).clamp(
              .25,
              1.0,
            );
      final color = f.$4;
      paint.color = Color.fromARGB(
        255,
        (color.r * 255 * light).round(),
        (color.g * 255 * light).round(),
        (color.b * 255 * light).round(),
      );
      final a = project(f.$1), b = project(f.$2), c = project(f.$3);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GiftPainter old) =>
      old.phase != phase || old.sku != sku;
}

class PulseGiftEffect extends StatefulWidget {
  const PulseGiftEffect({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    this.fast = false,
  });
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  final bool fast;
  @override
  State<PulseGiftEffect> createState() => _PulseGiftEffectState();
}

class _PulseGiftEffectState extends State<PulseGiftEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() {
    super.initState();
    controller =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: widget.fast ? 1000 : 2800),
          )
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) widget.onComplete();
          })
          ..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Opacity(
          opacity: (math.sin(t * math.pi) * 2).clamp(0, 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xdd172139),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: const Color(0xffffcb68)),
                ),
                child: Row(
                  children: [
                    PulseAvatar(
                      repo: widget.repo,
                      path: widget.event['avatar_path'],
                      userId: widget.event['sender_id'],
                      name: widget.event['display_name'],
                      radius: 20,
                    ),
                    PulseRankBadge(
                      rank: (widget.event['gifter']?['rank'] as num? ?? 0)
                          .toInt(),
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.event['is_test'] == true ? 'TEST · ' : ''}${widget.event['display_name']} sent ${widget.event['quantity']} × ${widget.event['title'].toString().replaceFirst('TEST · ', '')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 220,
                width: 260,
                child: CustomPaint(
                  painter: _GiftSparkles(t),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      widget.event['sku'] == 'rocket'
                          ? -80 * t
                          : math.sin(t * math.pi * 3) * 10,
                    ),
                    child: Transform.scale(
                      scale: .75 + .25 * math.sin(t * math.pi),
                      child: PulseGiftModel(sku: widget.event['sku'], phase: t),
                    ),
                  ),
                ),
              ),
              Text(
                '×${widget.event['quantity']}',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Color(0xffffdf87),
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _GiftSparkles extends CustomPainter {
  _GiftSparkles(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final p = Paint()..blendMode = BlendMode.plus;
    p.shader =
        RadialGradient(
          colors: [const Color(0x886d52ff), const Color(0x004ee7f4)],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * .5),
        );
    canvas.drawCircle(centre, size.shortestSide * .5, p);
    p.shader = null;
    for (var i = 0; i < 22; i++) {
      final a = i * 2.39996 + t * 1.6,
          r = (.15 + .7 * t) * size.shortestSide * .5 * (.5 + (i % 5) * .1);
      final pt = centre + Offset(math.cos(a) * r, math.sin(a) * r);
      p.color = (i.isEven ? const Color(0xffffdb83) : const Color(0xffa4eaff))
          .withValues(alpha: math.sin(t * math.pi).clamp(0, 1));
      canvas.drawCircle(pt, 1.5 + (i % 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GiftSparkles old) => old.t != t;
}
