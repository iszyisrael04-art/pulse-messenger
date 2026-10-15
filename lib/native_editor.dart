import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

const _editorChannel = MethodChannel('pulse/native_editor');
typedef _ExportNative =
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Int64, Int64, Int32);
typedef _ExportDart =
    int Function(Pointer<Utf16>, Pointer<Utf16>, int, int, int);
DynamicLibrary _library() => DynamicLibrary.open('pulse_editor.dll');
int _windowsExport((String, String, int, int, bool) p) {
  final input = p.$1.toNativeUtf16(), output = p.$2.toNativeUtf16();
  try {
    return _library().lookupFunction<_ExportNative, _ExportDart>(
      'pulse_editor_export',
    )(input, output, p.$3, p.$4, p.$5 ? 1 : 0);
  } finally {
    calloc.free(input);
    calloc.free(output);
  }
}

Future<int> _runExport((String, String, int, int, bool) args) =>
    Isolate.run(() => _windowsExport(args));

class NativePulseEditor {
  static Future<File> export(
    File input,
    File output,
    int startMs,
    int endMs,
    bool mute,
    void Function(double) onProgress,
  ) async {
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        final value = Platform.isWindows
            ? _library().lookupFunction<Double Function(), double Function()>(
                'pulse_editor_progress',
              )()
            : await _editorChannel.invokeMethod<double>('progress') ?? 0;
        onProgress(value.clamp(0, 1).toDouble());
      } catch (_) {}
    });
    try {
      if (Platform.isWindows) {
        final result = await _runExport((
          input.path,
          output.path,
          startMs,
          endMs,
          mute,
        ));
        if (result != 0)
          throw StateError(
            result == -3
                ? 'Export cancelled'
                : 'Windows could not export this codec. Try an MP4 video.',
          );
      } else if (Platform.isAndroid) {
        await _editorChannel.invokeMethod<Map>('export', {
          'input': input.path,
          'output': output.path,
          'startMs': startMs,
          'endMs': endMs,
          'mute': mute,
        });
      } else {
        throw UnsupportedError(
          'Native video export supports Android and Windows.',
        );
      }
      if (!await output.exists() || await output.length() == 0)
        throw StateError('No video was exported');
      onProgress(1);
      return output;
    } finally {
      timer.cancel();
    }
  }

  static Future<void> cancel() async {
    if (Platform.isWindows) {
      _library().lookupFunction<Void Function(), void Function()>(
        'pulse_editor_cancel',
      )();
    } else if (Platform.isAndroid) {
      await _editorChannel.invokeMethod<void>('cancel');
    }
  }

  static Future<void> saveDownload(File file, String name, String mime) async =>
      _editorChannel.invokeMethod<void>('saveDownload', {
        'input': file.path,
        'name': name,
        'mime': mime,
      });
}
