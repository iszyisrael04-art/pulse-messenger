import 'package:flutter/material.dart';

/// Loading stays behind the preview; only failures need an on-screen action.
class PulsePlaybackStatus extends StatelessWidget {
  const PulsePlaybackStatus({
    super.key,
    this.loading = false,
    this.message,
    this.onRetry,
  });
  final bool loading;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
        child: Material(
          color: const Color(0xff101821).withValues(alpha: .88),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message ?? 'Video couldn’t start. Try again.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (onRetry != null)
                  IconButton(
                    tooltip: 'Retry video',
                    onPressed: onRetry,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xff8cebd7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const pulseVideoGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff152e36), Color(0xff0d111b), Color(0xff231c37)],
  ),
);
