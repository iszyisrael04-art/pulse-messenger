import 'package:flutter/material.dart';
import 'profile_rules.dart';

/// A single media-backed header: identity and portrait share the same banner.
class PulseProfileHero extends StatelessWidget {
  const PulseProfileHero({
    super.key,
    required this.background,
    required this.avatar,
    required this.displayName,
    required this.username,
    required this.following,
    required this.followers,
    required this.likes,
    required this.actions,
    this.verified = false,
    this.onEdit,
    this.signal,
  });
  final Widget background, avatar;
  final String displayName, username;
  final Object? following, followers, likes;
  final List<Widget> actions;
  final bool verified;
  final VoidCallback? onEdit;
  final String? signal;

  Widget counts() => Row(
    key: const ValueKey('profile-hero-counts'),
    children: [
      for (final entry in {
        'Following': following,
        'Followers': followers,
        'Likes': likes,
      }.entries)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    compactProfileCount(entry.value),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
      final portraitSize = constraints.maxWidth < 380 ? 96.0 : 120.0;
      return ClipRect(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Stack(
              key: const ValueKey('profile-banner-header'),
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(child: background),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66000000),
                          Color(0x22000000),
                          Color(0xf5000000),
                        ],
                        stops: [0, .3, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (onEdit != null)
                            IconButton.filledTonal(
                              tooltip: 'Edit profile',
                              onPressed: onEdit,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black38,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          const Spacer(),
                          ...actions,
                        ],
                      ),
                      const SizedBox(height: 40),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: displayName),
                                      if (verified)
                                        const WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Icon(
                                              Icons.verified,
                                              color: Colors.blue,
                                              size: 21,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '@$username',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                                if (!largeText) ...[
                                  const SizedBox(height: 24),
                                  counts(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: portraitSize,
                            child: Column(
                              children: [
                                if ((signal ?? '').trim().isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      signal!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                SizedBox.square(
                                  key: const ValueKey('profile-hero-portrait'),
                                  dimension: portraitSize,
                                  child: FittedBox(child: avatar),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (largeText) ...[const SizedBox(height: 24), counts()],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
