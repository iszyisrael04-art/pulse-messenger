import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Remote hang-up also closes an open call options sheet or information dialog.
void pulseCloseCallRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  final navigator = Navigator.of(context);
  navigator.popUntil((r) => r == route || r.isFirst);
  if (route.isCurrent && navigator.canPop()) navigator.pop();
}

/// A video-first call surface. The small preview stays within the visible
/// viewport and snaps to a safe corner without covering the hang-up dock.
class PulseCallLayout extends StatefulWidget {
  const PulseCallLayout({
    super.key,
    required this.name,
    required this.status,
    required this.mainVideo,
    required this.onHangUp,
    required this.onMembers,
    required this.onMute,
    required this.muted,
    required this.videoCall,
    required this.camera,
    required this.speaker,
    this.previewVideo,
    this.groupVideos = const [],
    this.onCamera,
    this.onSwitchCamera,
    this.onSpeaker,
    this.controlsEnabled = true,
    this.error,
    this.onDetails,
    this.ending = false,
  });
  final String name, status;
  final Widget Function(bool fill) mainVideo;
  final Widget Function(bool fill)? previewVideo;
  final List<Widget> groupVideos;
  final VoidCallback onHangUp, onMembers;
  final VoidCallback? onMute, onCamera, onSwitchCamera, onSpeaker, onDetails;
  final bool muted, videoCall, camera, speaker, controlsEnabled, ending;
  final String? error;
  @override
  State<PulseCallLayout> createState() => _PulseCallLayoutState();
}

class _PulseCallLayoutState extends State<PulseCallLayout> {
  Offset corner = const Offset(1, 1);
  bool dragging = false, swapped = false, fill = true;

  Future<void> more() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              const ListTile(
                title: Text(
                  'Call options',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Participants'),
                onTap: () => Navigator.pop(sheet, 'members'),
              ),
              if (widget.previewVideo != null && widget.groupVideos.isEmpty)
                ListTile(
                  leading: const Icon(Icons.picture_in_picture_alt),
                  title: const Text('Swap video views'),
                  onTap: () => Navigator.pop(sheet, 'swap'),
                ),
              if (widget.videoCall)
                ListTile(
                  leading: const Icon(Icons.fit_screen),
                  title: Text(fill ? 'Fit whole video' : 'Fill the screen'),
                  onTap: () => Navigator.pop(sheet, 'fit'),
                ),
              if (widget.onSwitchCamera != null)
                ListTile(
                  leading: const Icon(Icons.cameraswitch_outlined),
                  title: const Text('Switch camera'),
                  enabled: widget.controlsEnabled && widget.camera,
                  onTap: () => Navigator.pop(sheet, 'camera'),
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Call information'),
                onTap: () => Navigator.pop(sheet, 'details'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'members':
        widget.onMembers();
        break;
      case 'swap':
        setState(() => swapped = !swapped);
        break;
      case 'fit':
        setState(() => fill = !fill);
        break;
      case 'camera':
        widget.onSwitchCamera?.call();
        break;
      case 'details':
        widget.onDetails?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      systemStatusBarContrastEnforced: false,
    ),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final safe = MediaQuery.paddingOf(context);
        final w = bounds.maxWidth, h = bounds.maxHeight;
        final short = h < 460;
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final header = short ? 64.0 : (32 + 60 * scale).clamp(92.0, 180.0);
        const dock = 88.0;
        final available = h - safe.top - safe.bottom - header - dock - 36;
        final hasPreview =
            widget.previewVideo != null &&
            widget.groupVideos.isEmpty &&
            available >= 72;
        final width = math.min(148.0, math.max(88.0, w * .33));
        final height = math.min(
          width * 1.48,
          math.min(224.0, math.max(72.0, available)),
        );
        final allowed = Rect.fromLTRB(
          12,
          safe.top + header + 8,
          math.max(12, w - width - 12),
          math.max(safe.top + header + 8, h - safe.bottom - dock - height - 20),
        );
        final offset = Offset(
          allowed.left + corner.dx * allowed.width,
          allowed.top + corner.dy * allowed.height,
        );
        final tools = widget.videoCall && !short && available >= 200;
        final main =
            swapped && widget.previewVideo != null && widget.groupVideos.isEmpty
            ? widget.previewVideo!
            : widget.mainVideo;
        final preview = swapped ? widget.mainVideo : widget.previewVideo;
        final button = math.min(58.0, (w - 56) / (widget.videoCall ? 5 : 4));
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xff0b141a)),
            if (widget.groupVideos.isEmpty)
              main(fill)
            else
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  safe.top + header + 8,
                  10,
                  safe.bottom + dock + 12,
                ),
                child: LayoutBuilder(
                  builder: (_, grid) {
                    final columns = w >= 760 && widget.groupVideos.length > 4
                        ? 3
                        : 2;
                    final rows = (widget.groupVideos.length / columns).ceil();
                    return GridView.count(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: columns,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio:
                          ((grid.maxWidth - (columns - 1) * 6) / columns) /
                          math.max(1, (grid.maxHeight - (rows - 1) * 6) / rows),
                      children: widget.groupVideos,
                    );
                  },
                ),
              ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .25, .65, 1],
                    colors: [
                      Colors.black45,
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black45,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: safe.top + 14,
              left: 64,
              right: 64,
              child: Semantics(
                label: '${widget.name}, ${widget.status}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      maxLines: short ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: short ? 19 : 23,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: safe.top + 14,
              left: 12,
              child: _CallButton(
                icon: Icons.info_outline,
                label: 'Call information',
                size: 40,
                onPressed: widget.onDetails,
              ),
            ),
            if (hasPreview && preview != null)
              AnimatedPositioned(
                key: const ValueKey('call-preview-position'),
                duration: dragging || MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: offset.dx,
                top: offset.dy,
                width: width,
                height: height,
                child: Semantics(
                  label: swapped
                      ? 'Other person preview. Tap to swap video views.'
                      : 'Your preview. Drag to move, tap to swap video views.',
                  button: true,
                  child: GestureDetector(
                    key: const ValueKey('call-preview'),
                    onTap: () => setState(() => swapped = !swapped),
                    onPanStart: (_) => setState(() => dragging = true),
                    onPanUpdate: (event) => setState(() {
                      final point =
                          Offset(
                            allowed.left + corner.dx * allowed.width,
                            allowed.top + corner.dy * allowed.height,
                          ) +
                          event.delta;
                      corner = Offset(
                        allowed.width <= 0
                            ? 0
                            : ((point.dx - allowed.left) / allowed.width).clamp(
                                0.0,
                                1.0,
                              ),
                        allowed.height <= 0
                            ? 0
                            : ((point.dy - allowed.top) / allowed.height).clamp(
                                0.0,
                                1.0,
                              ),
                      );
                    }),
                    onPanEnd: (_) => setState(() {
                      dragging = false;
                      // The top-right corner sits below the quick tools.
                      final rightTop = tools && allowed.height > 0
                          ? ((safe.top + header + 188 - allowed.top) /
                                    allowed.height)
                                .clamp(0.0, 1.0)
                          : 0.0;
                      final choices = [
                        Offset.zero,
                        Offset(1, rightTop),
                        const Offset(0, 1),
                        const Offset(1, 1),
                      ];
                      choices.sort(
                        (a, b) => (a - corner).distanceSquared.compareTo(
                          (b - corner).distanceSquared,
                        ),
                      );
                      corner = choices.first;
                    }),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white38, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 14,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: preview(true),
                      ),
                    ),
                  ),
                ),
              ),
            if (tools)
              Positioned(
                right: 14,
                top: safe.top + header + 8,
                child: Column(
                  children: [
                    _CallButton(
                      icon: Icons.people_outline,
                      label: 'Participants',
                      onPressed: widget.onMembers,
                    ),
                    const SizedBox(height: 12),
                    _CallButton(
                      icon: Icons.cameraswitch_outlined,
                      label: 'Switch camera',
                      onPressed: widget.controlsEnabled && widget.camera
                          ? widget.onSwitchCamera
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _CallButton(
                      icon: fill ? Icons.fit_screen : Icons.fullscreen,
                      label: fill ? 'Fit whole video' : 'Fill the screen',
                      onPressed: () => setState(() => fill = !fill),
                    ),
                  ],
                ),
              ),
            if (widget.error != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: safe.bottom + dock + 16,
                child: Material(
                  color: const Color(0xe02a2632),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: widget.onDetails,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: safe.bottom + 12,
              child: Center(
                child: Container(
                  key: const ValueKey('call-controls'),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xe0111c21),
                    borderRadius: BorderRadius.circular(46),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CallButton(
                        icon: Icons.more_horiz,
                        label: 'More call options',
                        size: button,
                        onPressed: more,
                      ),
                      if (widget.videoCall)
                        _CallButton(
                          icon: widget.camera
                              ? Icons.videocam
                              : Icons.videocam_off,
                          label: widget.camera
                              ? 'Turn camera off'
                              : 'Turn camera on',
                          size: button,
                          selected: !widget.camera,
                          onPressed: widget.controlsEnabled
                              ? widget.onCamera
                              : null,
                        ),
                      _CallButton(
                        icon: widget.speaker ? Icons.volume_up : Icons.hearing,
                        label: widget.speaker
                            ? 'Turn speaker off'
                            : 'Turn speaker on',
                        size: button,
                        selected: widget.speaker,
                        onPressed: widget.controlsEnabled
                            ? widget.onSpeaker
                            : null,
                      ),
                      _CallButton(
                        icon: widget.muted ? Icons.mic_off : Icons.mic,
                        label: widget.muted
                            ? 'Unmute microphone'
                            : 'Mute microphone',
                        size: button,
                        selected: widget.muted,
                        onPressed: widget.controlsEnabled
                            ? widget.onMute
                            : null,
                      ),
                      _CallButton(
                        key: const ValueKey('call-hangup'),
                        icon: Icons.call_end,
                        label: 'End call',
                        size: button,
                        destructive: true,
                        onPressed: widget.ending ? null : widget.onHangUp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.destructive = false,
    this.size = 50,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected, destructive;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: selected,
    button: true,
    child: SizedBox.square(
      dimension: size.clamp(40.0, 60.0),
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: destructive
              ? const Color(0xffff003b)
              : selected
              ? Colors.white
              : const Color(0xff222d32),
          foregroundColor: selected && !destructive
              ? Colors.black
              : Colors.white,
          disabledForegroundColor: selected ? Colors.black38 : Colors.white38,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: math.min(26, size * .48)),
      ),
    ),
  );
}
