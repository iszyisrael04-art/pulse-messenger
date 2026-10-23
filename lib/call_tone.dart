import 'dart:async';
import 'package:media_kit/media_kit.dart' as mk;

/// One player per call controller; transitions stop the old loop first.
class PulseCallTone {
  mk.Player? _player;
  String? _asset;
  bool _closed = false;
  int _generation = 0;
  Future<void> play(String? asset) async {
    if (_closed || asset == _asset) return;
    _asset = asset;
    final generation = ++_generation;
    final old = _player;
    _player = null;
    if (old != null) await old.dispose();
    if (_closed || generation != _generation || asset == null) return;
    final player = mk.Player();
    _player = player;
    try {
      await player.setPlaylistMode(mk.PlaylistMode.single);
      await player.setVolume(45);
      if (_closed || generation != _generation) return;
      await player.open(mk.Media('asset:///assets/audio/$asset.ogg'));
    } catch (_) {
      // A missing audio device must not prevent a call.
    }
  }

  void dispose() {
    _closed = true;
    _generation++;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
  }
}
