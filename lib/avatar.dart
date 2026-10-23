import 'dart:async';
import 'package:flutter/material.dart';
import 'profile_rules.dart';
import 'presence_widgets.dart';
import 'profile_media_rules.dart';
import 'video_avatar.dart';
import 'repository.dart' hide Row;

/// Uses a photo placeholder rather than initials. GIF and video motion are entitlement-aware.
class PulseAvatar extends StatefulWidget {
  const PulseAvatar({
    super.key,
    required this.repo,
    required this.path,
    required this.name,
    this.radius = 24,
    this.userId,
  });
  final PulseRepository repo;
  final String? path;
  final String name;
  final double radius;
  final String? userId;
  @override
  State<PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<PulseAvatar> {
  String? url, posterUrl;
  DateTime? expiry;
  Timer? refresh;
  int generation = 0;
  DateTime? observedMotion;
  @override
  void initState() {
    super.initState();
    observedMotion = widget.repo.motionUntil;
    load();
  }

  @override
  void didUpdateWidget(PulseAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.repo != widget.repo) {
      observedMotion = widget.repo.motionUntil;
      load();
    } else if (observedMotion != widget.repo.motionUntil) {
      observedMotion = widget.repo.motionUntil;
      load(motionOnly: true);
    }
  }

  Future<void> load({bool motionOnly = false}) async {
    final own = ++generation;
    refresh?.cancel();
    if (!motionOnly) {
      url = null;
      posterUrl = null;
      expiry = null;
    }
    try {
      final results = await Future.wait<Object?>([
        motionOnly
            ? Future<String?>.value(url)
            : widget.repo.avatar(widget.path),
        widget.repo.avatarMotionExpiry(widget.path),
        isProfileVideo(widget.path)
            ? widget.repo.avatar(profilePosterPath(widget.path!))
            : Future<String?>.value(null),
      ]);
      if (!mounted || own != generation) return;
      setState(() {
        url = results[0] as String?;
        expiry = results[1] as DateTime?;
        posterUrl = results[2] as String?;
      });
      if (expiry != null && expiry!.isAfter(DateTime.now())) {
        refresh = Timer(
          expiry!.difference(DateTime.now()) + const Duration(milliseconds: 20),
          () {
            if (!mounted) return;
            setState(() => expiry = null);
            load(motionOnly: true);
          },
        );
      }
    } catch (_) {
      // A denied, missing or offline image displays the same accessible photo icon.
      if (mounted && own == generation)
        setState(() {
          if (!motionOnly) url = null;
          expiry = null;
        });
    }
  }

  @override
  void dispose() {
    generation++;
    refresh?.cancel();
    super.dispose();
  }

  Widget portrait(BuildContext context) {
    if (url == null) return const PulsePhotoPlaceholder();
    if (!isProfileVideo(widget.path))
      return PulsePortrait(
        provider: ResizeImage(NetworkImage(url!), width: 256),
        animate: profileMotionAllowed(expiry, DateTime.now()),
      );
    final poster = posterUrl == null
        ? const PulsePhotoPlaceholder()
        : Image.network(
            posterUrl!,
            fit: BoxFit.cover,
            cacheWidth: 256,
            errorBuilder: (_, __, ___) => const PulsePhotoPlaceholder(),
          );
    final animate =
        widget.radius >= 40 &&
        profileMotionAllowed(
          expiry,
          DateTime.now(),
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          visible: TickerMode.of(context),
        );
    return animate
        ? PulseVideoAvatar(key: ValueKey(url), url: url!, poster: poster)
        : poster;
  }

  @override
  Widget build(BuildContext context) {
    final picture = Semantics(
      label: '${widget.name} profile picture',
      image: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: widget.radius * 2,
          child: portrait(context),
        ),
      ),
    );
    return widget.userId == null
        ? picture
        : PulseOnlineIndicator(
            presence: widget.repo.presence,
            userId: widget.userId!,
            child: picture,
          );
  }
}

class PulsePhotoPlaceholder extends StatelessWidget {
  const PulsePhotoPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        Icons.add_a_photo_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Keeps exactly one decoded frame when animation is unavailable or disabled.
/// This also prevents animated WebP/PNG from bypassing the paid motion-profile UI.
class PulsePortrait extends StatefulWidget {
  const PulsePortrait({
    super.key,
    required this.provider,
    this.animate = false,
  });
  final ImageProvider provider;
  final bool animate;
  @override
  State<PulsePortrait> createState() => _PulsePortraitState();
}

class _PulsePortraitState extends State<PulsePortrait> {
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? frame;
  ImageProvider? previous;
  bool? previousMotion;
  int generation = 0;
  void detach() {
    if (stream != null && listener != null) stream!.removeListener(listener!);
    stream = null;
    listener = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    resolve();
  }

  @override
  void didUpdateWidget(PulsePortrait old) {
    super.didUpdateWidget(old);
    resolve();
  }

  void resolve() {
    final motion =
        widget.animate &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (previous == widget.provider && previousMotion == motion) return;
    previous = widget.provider;
    previousMotion = motion;
    detach();
    final own = ++generation;
    final next = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    stream = next;
    listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted || generation != own) {
          info.dispose();
          return;
        }
        final old = frame;
        if (synchronous) {
          frame = info;
        } else {
          setState(() => frame = info);
        }
        if (old != null)
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        if (!motion) detach();
      },
      onError: (Object _, StackTrace? __) {
        if (mounted && generation == own) {
          final old = frame;
          setState(() => frame = null);
          if (old != null)
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          detach();
        }
      },
    );
    next.addListener(listener!);
  }

  @override
  void dispose() {
    generation++;
    detach();
    frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => frame == null
      ? const PulsePhotoPlaceholder()
      : RawImage(image: frame!.image, scale: frame!.scale, fit: BoxFit.cover);
}
