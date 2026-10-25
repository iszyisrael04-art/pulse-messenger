import 'package:flutter/material.dart';

int pulseLiveViewerCount(Iterable<String> remote, String? local, String? host) {
  if (host == null) return 0;
  return {...remote, if (local != null) local}.where((id) => id != host).length;
}

class PulseLiveMenuButton extends StatelessWidget {
  const PulseLiveMenuButton({
    super.key,
    required this.requests,
    required this.onPressed,
  });
  final int requests;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: requests > 0 ? 'LIVE menu · $requests seat requests' : 'LIVE menu',
    onPressed: onPressed,
    icon: Badge(
      isLabelVisible: requests > 0,
      label: Text('$requests'),
      child: const Icon(Icons.more_horiz, color: Colors.white),
    ),
  );
}

class PulseLiveComment extends StatelessWidget {
  const PulseLiveComment({
    super.key,
    required this.avatar,
    required this.name,
    required this.message,
    required this.openProfile,
    this.rank,
    this.moderate,
  });
  final Widget avatar;
  final Widget? rank;
  final String name, message;
  final VoidCallback openProfile;
  final VoidCallback? moderate;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: openProfile,
    onLongPress: moderate,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(label: 'Open $name profile', button: true, child: avatar),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (rank != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: rank!,
                      ),
                    ),
                  TextSpan(
                    text: '$name  ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xff8ce6d0),
                    ),
                  ),
                  TextSpan(
                    text: message,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          if (moderate != null)
            IconButton(
              tooltip: 'Moderate comment',
              onPressed: moderate,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.more_vert, color: Colors.white70),
            ),
        ],
      ),
    ),
  );
}

/// The mobile IME retains its paragraph key; the adjacent button submits.
class PulseLiveMessageField extends StatelessWidget {
  const PulseLiveMessageField({
    super.key,
    required this.controller,
    required this.enabled,
  });
  final TextEditingController controller;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    minLines: 1,
    maxLines: 3,
    maxLength: 500,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: enabled ? 'Say something…' : 'Comments paused',
      hintStyle: const TextStyle(color: Colors.white60),
      counterText: '',
      filled: true,
      fillColor: Colors.black45,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
}

/// Compact LIVE header keeps the camera visible and leaves a real close target.
class PulseLiveHeader extends StatelessWidget {
  const PulseLiveHeader({
    super.key,
    required this.avatar,
    required this.name,
    required this.viewers,
    required this.openProfile,
    required this.leave,
    this.follow,
    this.followLabel = '+ Follow',
  });
  final Widget avatar;
  final String name, followLabel;
  final int viewers;
  final VoidCallback openProfile;
  final VoidCallback? leave, follow;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 4, 6, 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                children: [
                  InkWell(onTap: openProfile, child: avatar),
                  const SizedBox(width: 7),
                  Expanded(
                    child: InkWell(
                      onTap: openProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xffff7198),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (follow != null)
                    TextButton(
                      onPressed: follow,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Color(0xffff3974),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                      ),
                      child: Text(
                        followLabel,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: '$viewers viewers',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$viewers',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Leave live',
            onPressed: leave,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}
