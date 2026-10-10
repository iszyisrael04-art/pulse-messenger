import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'media.dart';

class PulseVoiceNote {
  PulseVoiceNote(this.file, this.durationMs, this.waveform);
  final File file;
  final int durationMs;
  final List<double> waveform;
}

class VoiceRecorderDialog extends StatefulWidget {
  const VoiceRecorderDialog({super.key});
  @override
  State<VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<VoiceRecorderDialog>
    with WidgetsBindingObserver {
  final recorder = AudioRecorder();
  final clock = Stopwatch();
  final amplitudes = <double>[];
  StreamSubscription<Amplitude>? amplitudeSubscription;
  Timer? ticker;
  Player? preview;
  String? path, error;
  bool recording = false, paused = false, stopped = false, busy = true;
  bool handedOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> start() async {
    try {
      if (!await recorder.hasPermission()) {
        throw Exception(
          'Microphone access was denied. Enable it in system settings.',
        );
      }
      final directory = await getTemporaryDirectory();
      path = '${directory.path}/pulse-${const Uuid().v4()}.m4a';
      if (!mounted) return;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path!,
      );
      if (!mounted) {
        await recorder.cancel();
        return;
      }
      recording = true;
      clock.start();
      amplitudeSubscription = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (!paused && !stopped && mounted) {
              amplitudes.add(
                ((amplitude.current + 60) / 60).clamp(0.0, 1.0).toDouble(),
              );
            }
          });
      ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (clock.elapsed >= const Duration(minutes: 5) && !busy && !stopped) {
          stop();
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pauseOrResume() async {
    if (busy || stopped || !recording) return;
    setState(() => busy = true);
    try {
      if (paused) {
        await recorder.resume();
        clock.start();
      } else {
        await recorder.pause();
        clock.stop();
      }
      paused = !paused;
    } catch (_) {
      error = 'Microphone unavailable. Stop or discard this recording.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    if (busy || stopped || !recording) return;
    setState(() => busy = true);
    try {
      clock.stop();
      final result = await recorder.stop();
      await amplitudeSubscription?.cancel();
      ticker?.cancel();
      if (result == null || !await File(result).exists()) throw Exception();
      path = result;
      stopped = true;
      recording = false;
    } catch (_) {
      error = 'The recording could not be saved. Discard it and try again.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> listen() async {
    if (!stopped || path == null || busy) return;
    setState(() => busy = true);
    try {
      if (preview == null) {
        MediaKit.ensureInitialized();
        preview = Player();
        await PulseMedia.activate(preview!);
        await preview!.open(Media(path!));
      } else {
        await PulseMedia.activate(preview!);
        await preview!.seek(Duration.zero);
        await preview!.play();
      }
    } catch (_) {
      error = 'Preview unavailable. You can discard this note.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (!stopped || path == null || busy || clock.elapsedMilliseconds < 500)
      return;
    await preview?.pause();
    final samples = <double>[];
    final count = amplitudes.length > 96 ? 96 : amplitudes.length;
    for (var i = 0; i < count; i++) {
      final first = (i * amplitudes.length / count).floor();
      final last = ((i + 1) * amplitudes.length / count).floor();
      var peak = 0.0;
      for (var j = first; j < last; j++) {
        if (amplitudes[j] > peak) peak = amplitudes[j];
      }
      samples.add(peak);
    }
    if (!mounted) return;
    handedOff = true;
    Navigator.pop(
      context,
      PulseVoiceNote(
        File(path!),
        clock.elapsedMilliseconds.clamp(0, 300000),
        samples,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      preview?.pause();
      if (recording && !paused) pauseOrResume();
    }
  }

  Future<void> cleanup() async {
    await amplitudeSubscription?.cancel();
    if (recording) await recorder.cancel();
    await recorder.dispose();
    if (PulseMedia.active == preview) PulseMedia.active = null;
    await preview?.dispose();
    if (!handedOff && path != null) {
      final file = File(path!);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    unawaited(cleanup().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Voice note'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '${clock.elapsed.inMinutes}:${(clock.elapsed.inSeconds % 60).toString().padLeft(2, '0')} / 5:00',
            ),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: CustomPaint(
                painter: WaveformPainter(
                  List<double>.from(amplitudes),
                  Theme.of(context).colorScheme.primary,
                  progress: 1,
                ),
              ),
            ),
            if (error != null) Text(error!),
            if (recording)
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : pauseOrResume,
                    icon: Icon(paused ? Icons.mic : Icons.pause),
                    label: Text(paused ? 'Resume' : 'Pause'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
            if (stopped)
              TextButton.icon(
                onPressed: busy ? null : listen,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Listen from start'),
              ),
            const Text(
              'Stop to review and send. Keep Pulse open while recording.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: stopped && !busy && clock.elapsedMilliseconds >= 500
              ? send
              : null,
          child: const Text('Send'),
        ),
      ],
    ),
  );
}
