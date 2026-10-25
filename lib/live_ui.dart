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
