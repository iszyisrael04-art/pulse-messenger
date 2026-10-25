import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'gift_visuals.dart';

double _ease(double value) =>
    Curves.easeInOutCubic.transform(value.clamp(0.0, 1.0));
double _range(double t, double from, double to) =>
    _ease((t - from) / (to - from));
double _mix(double a, double b, double t) => a + (b - a) * t;

/// Authored phases, shared by the renderer and motion regression tests.
class PulseRocketPose {
  const PulseRocketPose(
    this.position,
    this.angle,
    this.scale,
    this.thrust,
    this.landed,
  );
  final Offset position;
  final double angle, scale, thrust;
  final bool landed;
}

PulseRocketPose pulseRocketPose(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < .22) {
    final a = _range(t, 0, .22);
    return PulseRocketPose(
      Offset(_mix(.48, .52, a), _mix(.94, .39, a)),
      _mix(0, -.2, a),
      _mix(.86, .60, a),
      _range(t, 0, .045),
      false,
    );
  }
  if (t < .55) {
    final a = _range(t, .22, .55);
    return PulseRocketPose(
      Offset(_mix(.52, .70, a), _mix(.39, .32, a)),
      _mix(-.2, -.65, a),
      _mix(.60, .45, a),
      1 - a * .45,
      false,
    );
  }
  final a = _range(t, .55, .85);
  return PulseRocketPose(
    Offset(_mix(.70, .54, a), _mix(.32, .58, a)),
    _mix(-.65, 0, a),
    _mix(.45, .80, a),
    t < .85 ? .35 + .25 * math.sin(a * math.pi) : 0,
    t >= .85,
  );
}

double pulseKingWalk(double t) => _range(t, .38, .78);
double pulseCastleGate(double t) => _range(t, .18, .40);

class PulseGiftStoryScene extends StatelessWidget {
  const PulseGiftStoryScene({
    super.key,
    required this.sku,
    required this.phase,
  });
  final String sku;
  final double phase;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _StoryPainter(sku, phase), size: Size.infinite),
  );
}

class _Instance {
  const _Instance(
    this.mesh, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.scale = 1,
    this.yaw = 0,
    this.roll = 0,
  });
  final GiftMesh mesh;
  final double x, y, z, scale, yaw, roll;
}

void _box(
  GiftMesh m,
  double x,
  double y,
  double z,
  double w,
  double h,
  double d,
  Color color,
) {
  final v = [
    for (var i = 0; i < 8; i++)
      GiftVertex(
        x + ((i & 1) == 0 ? -w : w) / 2,
        y + ((i & 2) == 0 ? -h : h) / 2,
        z + ((i & 4) == 0 ? -d : d) / 2,
      ),
  ];
  for (final f in [
    [0, 2, 3, 1],
    [4, 5, 7, 6],
    [0, 1, 5, 4],
    [2, 6, 7, 3],
    [0, 4, 6, 2],
    [1, 3, 7, 5],
  ]) {
    m.triangle(v[f[0]], v[f[1]], v[f[2]], color);
    m.triangle(v[f[0]], v[f[2]], v[f[3]], color);
  }
}

const _gold = Color(0xffffce65),
    _stone = Color(0xffb0abc1),
    _blue = Color(0xff314c92);

class _StoryModels {
  static final rocket = _rocket();
  static final flame = _flame();
  static final legs = _legs();
  static final castle = _castle();
  static final king = _king();
  static final arm = _arm();
  static final boot = _boot();
  static final leftDoor = _door(false), rightDoor = _door(true);
  static GiftMesh _rocket() {
    final m = GiftMesh();
    m.cone(
      0,
      -.8,
      0,
      .33,
      1.55,
      const Color(0xffdce8ee),
      top: .33,
      segments: 24,
    );
    m.cone(0, .75, 0, .34, .72, const Color(0xffd63f59), segments: 24);
    m.cone(0, -.95, 0, .24, .18, const Color(0xff3c4660), top: .30);
    for (final y in [-.65, .58])
      m.cone(0, y, 0, .345, .08, _gold, top: .345, segments: 24);
    m.sphere(0, .22, .32, .20, .22, .055, _gold);
    m.sphere(0, .22, .37, .15, .17, .035, const Color(0xff35c9ee));
    m.sphere(-.04, .27, .4, .05, .08, .006, const Color(0xffc9faff));
    for (final side in [-1, 1]) {
      _box(m, side * .43, -.65, 0, .20, .54, .16, const Color(0xffb92746));
      m.triangle(
        GiftVertex(side * .32, -.12, .08),
        GiftVertex(side * .62, -.90, .08),
        GiftVertex(side * .32, -.9, .08),
        const Color(0xfff15367),
      );
    }
    _box(m, 0, -.65, -.36, .15, .5, .3, const Color(0xffd63f59));
    return m;
  }

  static GiftMesh _flame() {
    final m = GiftMesh();
    m.cone(
      0,
      -2.5,
      0,
      0,
      1.55,
      const Color(0xfff48932),
      top: .22,
      segments: 20,
    );
    m.cone(
      0,
      -1.9,
      .03,
      0,
      .95,
      const Color(0xffa2ecff),
      top: .15,
      segments: 20,
    );
    return m;
  }

  static GiftMesh _legs() {
    final m = GiftMesh();
    for (final x in [-.46, .46]) {
      _box(m, x, -1.04, 0, .07, .5, .1, _gold);
      _box(m, x, -1.28, .03, .27, .09, .28, const Color(0xff526174));
    }
    return m;
  }

  static GiftMesh _castle() {
    final m = GiftMesh(), rng = math.Random(12);
    // Individual beveled-looking stone courses, a real open gate and four turrets.
    for (var course = 0; course < 6; course++) {
      for (var col = 0; col < 10; col++) {
        final x = (col - 4.5) * .27;
        if (course < 4 && x.abs() < .5) continue;
        _box(
          m,
          x,
          -.85 + course * .26,
          .68,
          .258,
          .247,
          .30,
          Color.lerp(_stone, Colors.white, rng.nextDouble() * .22)!,
        );
      }
    }
    _box(m, 0, -.1, -.7, 2.5, 1.75, .3, _stone);
    for (final x in [-1.35, 1.35]) {
      for (final z in [-.65, .68]) {
        m.cone(x, -1, z, .33, 2.1, _stone, top: .33, segments: 20);
        for (var row = 0; row < 7; row++) {
          m.cone(
            x,
            -.9 + row * .28,
            z,
            .345,
            .035,
            const Color(0xff7b7c98),
            top: .345,
            segments: 20,
          );
        }
        m.cone(x, 1.1, z, .46, .85, _blue, segments: 20);
        m.sphere(x, 1.98, z, .07, .07, .07, _gold);
        _box(m, x, .45, z + .325, .13, .38, .035, const Color(0xff333c5d));
      }
    }
    for (var i = 0; i < 9; i++)
      _box(m, (i - 4) * .29, .83, .68, .16, .22, .36, _stone);
    _box(m, 0, .65, -.35, 1.1, 1.9, .75, const Color(0xffc9c1d4));
    m.cone(0, 1.6, -.35, .8, .65, _blue, segments: 4);
    _box(m, 0, 2.6, -.35, .035, .75, .035, _gold);
    _box(m, .25, 2.8, -.35, .48, .26, .025, const Color(0xffbb335d));
    m.gem(.25, 2.8, -.32, .075, _gold, sides: 4);
    return m;
  }

  static GiftMesh _door(bool right) {
    final m = GiftMesh();
    for (var i = 0; i < 4; i++) {
      _box(
        m,
        (right ? -1 : 1) * (.055 + i * .105),
        -.46,
        0,
        .10,
        1.05,
        .09,
        i.isEven ? const Color(0xff623b35) : const Color(0xff7b4d3a),
      );
    }
    for (final y in [-.8, -.17])
      _box(m, right ? -.22 : .22, y, .055, .43, .06, .04, _gold);
    m.sphere(right ? -.35 : .35, -.5, .08, .035, .05, .02, _gold);
    return m;
  }

  static GiftMesh _king() {
    final m = GiftMesh();
    m.cone(0, -.22, 0, .32, .88, const Color(0xffa3284c), top: .22);
    m.cone(0, -.23, 0, .335, .07, _gold, top: .335);
    m.cone(0, .45, 0, .23, .07, _gold, top: .23);
    m.sphere(0, .53, .14, .12, .18, .1, const Color(0xfff1c554));
    m.gem(0, .55, .24, .06, const Color(0xff55e5dd));
    m.cone(0, .64, 0, .075, .16, const Color(0xffc88551), top: .075);
    m.sphere(0, 1.0, 0, .23, .29, .22, const Color(0xffc88551));
    m.sphere(0, .88, .16, .19, .20, .11, const Color(0xff452c2c));
    m.sphere(0, 1.03, .22, .05, .07, .055, const Color(0xffd69a62));
    for (final x in [-.09, .09]) {
      m.sphere(x, 1.1, .205, .035, .04, .018, const Color(0xff242836));
      m.sphere(x - .007, 1.11, .224, .009, .012, .005, Colors.white);
    }
    m.cone(0, 1.21, 0, .235, .13, _gold, top: .24, segments: 20);
    for (var i = 0; i < 7; i++) {
      final a = i * math.pi * 2 / 7;
      m.cone(math.cos(a) * .22, 1.34, math.sin(a) * .22, .05, .20, _gold);
      m.gem(
        math.cos(a) * .23,
        1.29,
        math.sin(a) * .23,
        .045,
        const Color(0xff5ad3f2),
      );
    }
    return m;
  }

  static GiftMesh _arm() {
    final m = GiftMesh();
    m.cone(0, -.5, 0, .09, .5, const Color(0xffab3152), top: .11);
    m.sphere(0, -.52, 0, .085, .11, .085, const Color(0xffc88551));
    m.cone(0, -.43, 0, .095, .045, _gold, top: .095);
    return m;
  }

  static GiftMesh _boot() {
    final m = GiftMesh();
    _box(m, 0, -.15, 0, .13, .32, .16, const Color(0xff343048));
    _box(m, 0, -.33, .07, .16, .12, .29, const Color(0xff343048));
    return m;
  }
}

class _StoryPainter extends CustomPainter {
  _StoryPainter(this.sku, this.t);
  final String sku;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    if (sku == 'rocket') _space(canvas, size);
    if (sku == 'castle') _royal(canvas, size);
    if (sku == 'crown') _sparkles(canvas, size, 36, Colors.amberAccent);
  }

  void _sparkles(Canvas c, Size s, int count, Color color) {
    final rng = math.Random(86);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * s.width;
      final y = ((rng.nextDouble() + t * .12) % 1) * s.height;
      final alpha =
          (.3 + .7 * math.sin(i + t * 16).abs()) * math.sin(t * math.pi);
      final paint = Paint()..color = color.withValues(alpha: alpha.clamp(0, 1));
      final r = 1 + rng.nextDouble() * 2;
      c.drawLine(
        Offset(x - r * 2, y),
        Offset(x + r * 2, y),
        paint..strokeWidth = 1,
      );
      c.drawLine(Offset(x, y - r * 2), Offset(x, y + r * 2), paint);
    }
  }

  void _planet(
    Canvas c,
    Offset center,
    double radius,
    Color light,
    Color dark,
  ) {
    c.drawCircle(
      center,
      radius * 1.035,
      Paint()
        ..color = light.withValues(alpha: .16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.55, -.55),
          radius: 1.15,
          colors: [light, dark],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _space(Canvas c, Size s) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff070c29), Color(0xff201237), Color(0xff020610)],
        ).createShader(Offset.zero & s),
    );
    for (var i = 0; i < 4; i++) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(s.width * (.2 + i * .2), s.height * (.24 + i * .13)),
          width: s.width * .9,
          height: s.height * .14,
        ),
        Paint()
          ..color = (i.isEven ? Colors.deepPurpleAccent : Colors.cyan)
              .withValues(alpha: .07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    final pose = pulseRocketPose(t), rng = math.Random(53);
    for (var i = 0; i < 120; i++) {
      final x = rng.nextDouble() * s.width;
      final y = ((rng.nextDouble() + t * (t < .6 ? 1.4 : .15)) % 1) * s.height;
      final length = t < .55 ? pose.thrust * (3 + rng.nextDouble() * 17) : 1.0;
      c.drawLine(
        Offset(x, y),
        Offset(x - length * .35, y + length),
        Paint()
          ..color = Colors.white.withValues(alpha: .25 + rng.nextDouble() * .5)
          ..strokeWidth = .5 + rng.nextDouble(),
      );
    }
    final earth = Offset(s.width * (.12 - t * .4), s.height * (.88 + t * .8));
    final er = s.width * .50;
    _planet(c, earth, er, const Color(0xff53bdda), const Color(0xff041029));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: earth, radius: er)));
    for (var i = 0; i < 12; i++) {
      c.drawOval(
        Rect.fromCenter(
          center:
              earth +
              Offset(math.cos(i * 2.4) * er * .65, math.sin(i * 2.4) * er * .7),
          width: er * .5,
          height: er * .16,
        ),
        Paint()..color = const Color(0xff318c80).withValues(alpha: .6),
      );
    }
    c.restore();
    final approach = _range(t, .5, .81);
    final mr = _mix(s.width * .08, s.height * .94, approach);
    final moon = Offset(
      _mix(s.width * .84, s.width * .54, approach),
      _mix(s.height * .28, s.height * .70 + mr, approach),
    );
    _planet(c, moon, mr, const Color(0xffdbddea), const Color(0xff42495b));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: moon, radius: mr)));
    final craters = math.Random(10);
    for (var i = 0; i < 65; i++) {
      final angle = craters.nextDouble() * math.pi * 2,
          r = math.sqrt(craters.nextDouble()) * mr;
      final p = moon + Offset(math.cos(angle) * r, math.sin(angle) * r);
      final w = mr * (.025 + craters.nextDouble() * .08);
      c.drawOval(
        Rect.fromCenter(center: p, width: w, height: w * .42),
        Paint()..color = const Color(0xff2f354b).withValues(alpha: .30),
      );
      c.drawArc(
        Rect.fromCenter(
          center: p + const Offset(0, 1),
          width: w,
          height: w * .42,
        ),
        0,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: .22),
      );
    }
    c.restore();
    if (t > .7) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(s.width * .54, s.height * .705),
          width: s.width * .28,
          height: s.height * .018,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: .3 * approach)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    final nodes = <_Instance>[_Instance(_StoryModels.rocket, roll: pose.angle)];
    if (pose.thrust > 0)
      nodes.add(
        _Instance(
          _StoryModels.flame,
          scale: (.65 + pose.thrust * .4 + math.sin(t * 170) * .06),
          roll: pose.angle,
        ),
      );
    if (t > .66)
      nodes.add(
        _Instance(
          _StoryModels.legs,
          roll: pose.angle,
          scale: _range(t, .66, .79),
        ),
      );
    _drawModels(
      c,
      s,
      nodes,
      center: Offset(pose.position.dx * s.width, pose.position.dy * s.height),
      unit: s.width * .22 * pose.scale,
      camera: 6,
      focal: 6,
    );
    if (t > .83) {
      final dust = _range(t, .83, .96);
      for (var i = 0; i < 24; i++) {
        final a = i * 2.4;
        c.drawCircle(
          Offset(
            s.width * .54 + math.cos(a) * dust * s.width * .32,
            s.height * .70 - math.sin(a).abs() * dust * s.height * .05,
          ),
          2 + dust * 7,
          Paint()
            ..color = const Color(
              0xffdbe0ee,
            ).withValues(alpha: (1 - dust) * .6),
        );
      }
    }
    if (t > .90) {
      final flag = _range(t, .90, .98), x = s.width * .74, y = s.height * .70;
      c.drawLine(
        Offset(x, y),
        Offset(x, y - s.height * .11 * flag),
        Paint()
          ..color = _gold
          ..strokeWidth = 2,
      );
      c.drawPath(
        Path()
          ..moveTo(x, y - s.height * .11 * flag)
          ..lineTo(x + s.width * .12, y - s.height * .095 * flag)
          ..lineTo(x + s.width * .12, y - s.height * .055 * flag)
          ..lineTo(x, y - s.height * .07 * flag)
          ..close(),
        Paint()..color = const Color(0xff64e3ce),
      );
    }
  }

  void _royal(Canvas c, Size s) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff211d49), Color(0xff9a6787), Color(0xffd6a57f)],
        ).createShader(Offset.zero & s),
    );
    _planet(
      c,
      Offset(s.width * .77, s.height * .23),
      s.width * .16,
      const Color(0xffffe3b0),
      const Color(0xffc8858b),
    );
    for (var i = 0; i < 3; i++) {
      c.drawPath(
        Path()
          ..moveTo(0, s.height * (.59 + i * .06))
          ..quadraticBezierTo(
            s.width * .25,
            s.height * (.35 + i * .1),
            s.width * .62,
            s.height * .6,
          )
          ..quadraticBezierTo(
            s.width * .8,
            s.height * .43,
            s.width,
            s.height * .58,
          )
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()
          ..color = [
            const Color(0xff3d4866),
            const Color(0xff354d59),
            const Color(0xff263f48),
          ][i],
      );
    }
    c.drawPath(
      Path()
        ..moveTo(s.width * .43, s.height * .57)
        ..lineTo(s.width * .57, s.height * .57)
        ..lineTo(s.width * .95, s.height)
        ..lineTo(s.width * .05, s.height)
        ..close(),
      Paint()..color = const Color(0xffa3939b),
    );
    for (var i = 0; i < 7; i++) {
      final y = s.height * (.59 + i * .055);
      c.drawLine(
        Offset(s.width * (.41 - i * .055), y),
        Offset(s.width * (.59 + i * .055), y),
        Paint()
          ..color = const Color(0xff6f657e)
          ..strokeWidth = 2,
      );
    }
    final walk = pulseKingWalk(t), gate = pulseCastleGate(t);
    final z = _mix(-2.6, 2.6, walk),
        sway = math.sin(t * 55) * .11 * (walk > 0 && walk < 1 ? 1 : 0);
    final nodes = <_Instance>[
      _Instance(_StoryModels.castle, z: -2),
      _Instance(_StoryModels.leftDoor, x: -.43, z: -1.15, yaw: -gate * 1.4),
      _Instance(_StoryModels.rightDoor, x: .43, z: -1.15, yaw: gate * 1.4),
      _Instance(_StoryModels.king, y: -.58 + sway.abs() * .16, z: z),
      _Instance(_StoryModels.boot, x: -.14, y: -.59, z: z + sway, roll: sway),
      _Instance(_StoryModels.boot, x: .14, y: -.59, z: z - sway, roll: -sway),
      _Instance(_StoryModels.arm, x: -.25, y: .07, z: z, roll: -.18 - sway),
      _Instance(
        _StoryModels.arm,
        x: .25,
        y: .07,
        z: z,
        roll: .18 + _range(t, .76, .85) * (2.0 + math.sin(t * 65) * .18),
      ),
    ];
    _drawModels(
      c,
      s,
      nodes,
      center: Offset(s.width * .5, s.height * .55),
      unit: s.width * .28,
    );
    if (t > .7) _sparkles(c, s, 42, _gold);
  }

  void _drawModels(
    Canvas c,
    Size s,
    List<_Instance> nodes, {
    required Offset center,
    required double unit,
    double camera = 8,
    double focal = 6,
  }) {
    final faces = <(GiftVertex, GiftVertex, GiftVertex, Color)>[];
    for (final n in nodes) {
      GiftVertex transform(GiftVertex v) {
        final x = v.x * n.scale, y = v.y * n.scale, z = v.z * n.scale;
        final a = x * math.cos(n.yaw) + z * math.sin(n.yaw);
        final b = z * math.cos(n.yaw) - x * math.sin(n.yaw);
        final px = a * math.cos(n.roll) - y * math.sin(n.roll) + n.x;
        final py = a * math.sin(n.roll) + y * math.cos(n.roll) + n.y;
        final pz = b + n.z;
        return GiftVertex(px, py * .995 + pz * .10, pz * .995 - py * .10);
      }

      for (final f in n.mesh.faces)
        faces.add((transform(f.a), transform(f.b), transform(f.c), f.color));
    }
    faces.sort(
      (a, b) => (a.$1.z + a.$2.z + a.$3.z).compareTo(b.$1.z + b.$2.z + b.$3.z),
    );
    Offset project(GiftVertex v) {
      final p = focal / (camera - v.z).clamp(.8, 30);
      return center + Offset(v.x * p * unit, -v.y * p * unit);
    }

    final paint = Paint()..isAntiAlias = true;
    for (final f in faces) {
      final ux = f.$2.x - f.$1.x, uy = f.$2.y - f.$1.y, uz = f.$2.z - f.$1.z;
      final vx = f.$3.x - f.$1.x, vy = f.$3.y - f.$1.y, vz = f.$3.z - f.$1.z;
      final nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length < .000001) continue;
      final light =
          (.45 + .55 * ((nx * -.35 + ny * .6 + nz * .72) / length).abs()).clamp(
            .25,
            1.0,
          );
      final shine =
          math
              .pow(((nx * -.2 + ny * .25 + nz * .94) / length).abs(), 24)
              .toDouble() *
          .4;
      final base = Color.fromARGB(
        255,
        (f.$4.r * 255 * light).round(),
        (f.$4.g * 255 * light).round(),
        (f.$4.b * 255 * light).round(),
      );
      paint.color = Color.lerp(base, Colors.white, shine)!;
      final a = project(f.$1), b = project(f.$2), d = project(f.$3);
      c.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(d.dx, d.dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StoryPainter old) =>
      old.t != t || old.sku != sku;
}
