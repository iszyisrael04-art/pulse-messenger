import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'gifter_rules.dart';
import 'social_repository.dart' show socialError;
export 'gifter_rules.dart';

const _rankColors = [
  Color(0xff91a6b9),
  Color(0xff65dcd2),
  Color(0xffcd8a53),
  Color(0xffc7e3f1),
  Color(0xffffc750),
  Color(0xffbfa5ff),
  Color(0xff35e7a4),
  Color(0xff53dfff),
  Color(0xff9873ff),
  Color(0xffff5894),
  Color(0xffffdd8c),
];

class PulseRankBadge extends StatelessWidget {
  const PulseRankBadge({
    super.key,
    required this.rank,
    this.size = 30,
    this.label = false,
  });
  final int rank;
  final double size;
  final bool label;
  @override
  Widget build(BuildContext context) {
    if (rank < 1 || rank > 10) return const SizedBox.shrink();
    return Semantics(
      label: 'Gifter rank $rank ${pulseGifterNames[rank]}',
      child: Tooltip(
        message: '${pulseGifterNames[rank]} · Gifter $rank',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: Size(size, size), painter: _RankPainter(rank)),
            if (label)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  pulseGifterNames[rank],
                  style: TextStyle(
                    color: _rankColors[rank],
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankPainter extends CustomPainter {
  _RankPainter(this.rank);
  final int rank;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 100, s.height / 100);
    final color = _rankColors[rank];
    final p = Paint()..isAntiAlias = true;
    // Metallic shield, faceted centre and tier-specific crown/wings.
    final shield = Path()
      ..moveTo(50, 5)
      ..lineTo(86, 22)
      ..lineTo(80, 67)
      ..lineTo(50, 96)
      ..lineTo(20, 67)
      ..lineTo(14, 22)
      ..close();
    p.shader = LinearGradient(
      colors: [Colors.white, color, const Color(0xff302448), color],
      stops: const [0, .3, .7, 1],
    ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    c.drawPath(shield, p);
    p.shader = null;
    p.color = const Color(0xff101729);
    c.drawPath(
      Path()
        ..moveTo(50, 16)
        ..lineTo(76, 29)
        ..lineTo(71, 62)
        ..lineTo(50, 82)
        ..lineTo(29, 62)
        ..lineTo(24, 29)
        ..close(),
      p,
    );
    p.color = color;
    c.drawPath(
      Path()
        ..moveTo(50, 25)
        ..lineTo(66, 46)
        ..lineTo(50, 67)
        ..lineTo(34, 46)
        ..close(),
      p,
    );
    p.color = Colors.white.withValues(alpha: .65);
    c.drawPath(
      Path()
        ..moveTo(50, 25)
        ..lineTo(50, 67)
        ..lineTo(34, 46)
        ..close(),
      p,
    );
    if (rank >= 5) {
      p.color = color;
      for (final sign in [-1, 1]) {
        c.drawPath(
          Path()
            ..moveTo(50 + sign * 32.0, 40)
            ..lineTo(50 + sign * 49.0, 24)
            ..lineTo(50 + sign * 43.0, 58)
            ..lineTo(50 + sign * 28.0, 69)
            ..close(),
          p,
        );
      }
    }
    if (rank >= 8) {
      p.color = color;
      c.drawPath(
        Path()
          ..moveTo(30, 22)
          ..lineTo(26, 3)
          ..lineTo(42, 12)
          ..lineTo(50, 0)
          ..lineTo(58, 12)
          ..lineTo(74, 3)
          ..lineTo(70, 22)
          ..close(),
        p,
      );
    }
    final text = TextPainter(
      text: TextSpan(
        text: '$rank',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(c, Offset(50 - text.width / 2, 67));
    if (rank == 10) {
      p.color = Colors.white;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        c.drawCircle(
          Offset(50 + 42 * math.cos(a), 50 + 42 * math.sin(a)),
          2,
          p,
        );
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _RankPainter old) => old.rank != rank;
}

class PulseGifterIdentity extends StatefulWidget {
  const PulseGifterIdentity({
    super.key,
    required this.repo,
    required this.user,
  });
  final PulseRepository repo;
  final String user;
  @override
  State<PulseGifterIdentity> createState() => _PulseGifterIdentityState();
}

class _PulseGifterIdentityState extends State<PulseGifterIdentity> {
  Map? data;
  Timer? refreshTimer;
  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => load());
  }

  @override
  void didUpdateWidget(covariant PulseGifterIdentity old) {
    super.didUpdateWidget(old);
    if (old.user != widget.user) load();
  }

  Future<void> load() async {
    try {
      final r = await widget.repo.rpc('gifter_status', {'p_user': widget.user});
      if (mounted) setState(() => data = r as Map?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => data == null
      ? const SizedBox.shrink()
      : Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            PulseRankBadge(
              rank: (data!['rank'] as num? ?? 0).toInt(),
              size: 36,
              label: true,
            ),
            if (data!['coins_spent'] != null && data!['show_spend'] == true)
              Text(
                '${data!['coins_spent']} LIVE coins',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        );
}

class PulseGifterRanksPage extends StatefulWidget {
  const PulseGifterRanksPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseGifterRanksPage> createState() => _PulseGifterRanksPageState();
}

class _PulseGifterRanksPageState extends State<PulseGifterRanksPage> {
  Map? data;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool? rank, bool? spend}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.repo.rpc('gifter_status', {
        'p_user': widget.repo.uid,
        if (rank != null) 'p_show_rank': rank,
        if (spend != null) 'p_show_spend': spend,
      });
      if (mounted)
        setState(() {
          data = r as Map?;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gifter ranks')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        const Text(
          'Your LIVE legacy',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (data != null) ...[
          Center(
            child: PulseRankBadge(
              rank: (data!['rank'] as num).toInt(),
              size: 110,
              label: true,
            ),
          ),
          Text(
            '${data!['coins_spent']} normal coins spent on LIVE gifts',
            textAlign: TextAlign.center,
          ),
          ListTile(
            title: const Text('Rank badge visibility'),
            subtitle: Text(
              data!['show_rank'] == true
                  ? 'Visible in your profile, LIVE chat and gift banners'
                  : 'Hidden from other users',
            ),
            trailing: IconButton(
              tooltip: 'Toggle rank visibility',
              onPressed: busy
                  ? null
                  : () => load(rank: data!['show_rank'] != true),
              icon: Icon(
                data!['show_rank'] == true
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
            ),
          ),
          ListTile(
            title: const Text('Spending total visibility'),
            subtitle: Text(
              data!['show_spend'] == true
                  ? 'Public: other users can see your coin total'
                  : 'Private: only you can see your exact total',
            ),
            trailing: IconButton(
              tooltip: 'Toggle spending visibility',
              onPressed: busy
                  ? null
                  : () => load(spend: data!['show_spend'] != true),
              icon: Icon(
                data!['show_spend'] == true
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
            ),
          ),
        ],
        const Text(
          'Ranks count normal coins actually spent on LIVE gifts across all broadcasts. Buying coins and tapping Like do not increase rank. A visible rank reveals its spending range, even when your exact total is private.',
        ),
        const SizedBox(height: 16),
        for (var i = 1; i <= 10; i++)
          Card(
            child: ListTile(
              leading: PulseRankBadge(rank: i, size: 52),
              title: Text('$i · ${pulseGifterNames[i]}'),
              subtitle: Text(
                '${pulseGifterThresholds[i - 1]} total LIVE coins',
              ),
              trailing: data?['rank'] == i
                  ? const Icon(Icons.check_circle)
                  : null,
            ),
          ),
      ],
    ),
  );
}
