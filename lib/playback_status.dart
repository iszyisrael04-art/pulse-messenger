import 'package:flutter/material.dart';

/// Shared, bounded-loading presentation for Home and Reels.
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
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 290),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xff101821).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loading
                ? Icons.play_circle_outline_rounded
                : Icons.wifi_off_rounded,
            color: const Color(0xff8cebd7),
            size: 36,
          ),
          const SizedBox(height: 14),
          Text(
            loading ? 'Getting your video ready' : 'Video couldn’t start',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message ??
                (loading
                    ? 'Connecting to Pulse…'
                    : 'Check your connection and try again.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ),
        ],
      ),
    ),
  );
}

const pulseVideoGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff152e36), Color(0xff0d111b), Color(0xff231c37)],
  ),
);
