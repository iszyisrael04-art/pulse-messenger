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

typedef _WatermarkNative =
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>);
typedef _WatermarkDart =
    int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>);
int _windowsWatermark((String, String, String) args) {
  final input = args.$1.toNativeUtf16(),
      output = args.$2.toNativeUtf16(),
      logo = args.$3.toNativeUtf16();
  try {
    return _library().lookupFunction<_WatermarkNative, _WatermarkDart>(
      'pulse_editor_watermark',
    )(input, output, logo);
  } finally {
    calloc.free(input);
    calloc.free(output);
    calloc.free(logo);
  }
}

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
      } else if (Platform.isAndroid || Platform.isIOS) {
        await _editorChannel.invokeMethod<Map>('export', {
          'input': input.path,
          'output': output.path,
          'startMs': startMs,
          'endMs': endMs,
          'mute': mute,
        });
      } else {
        throw UnsupportedError(
          'Native video export supports Android, iOS and Windows.',
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

  static Future<File> avatar(
    File input,
    File output,
    int startMs,
    int endMs,
    void Function(double) onProgress,
  ) async {
    if (startMs < 0 || endMs <= startMs || endMs - startMs > 5000)
      throw ArgumentError('Profile clips must be at most five seconds');
    if (Platform.isWindows)
      return export(input, output, startMs, endMs, true, onProgress);
    if (!Platform.isAndroid && !Platform.isIOS)
      throw UnsupportedError('Video avatars support Android, iOS and Windows');
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        onProgress(
          (await _editorChannel.invokeMethod<double>('progress') ?? 0)
              .clamp(0, 1)
              .toDouble(),
        );
      } catch (_) {}
    });
    try {
      await _editorChannel.invokeMethod<void>('avatar', {
        'input': input.path,
        'output': output.path,
        'startMs': startMs,
        'endMs': endMs,
      });
      if (!await output.exists() || await output.length() == 0)
        throw StateError('No profile video was exported');
      onProgress(1);
      return output;
    } finally {
      timer.cancel();
    }
  }

  static Future<File> style(
    File input,
    File output,
    Map<String, dynamic> settings,
    void Function(double) onProgress,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS)
      throw UnsupportedError('Video style export requires Android or iOS.');
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        onProgress(
          (await _editorChannel.invokeMethod<double>('progress') ?? 0)
              .clamp(0, 1)
              .toDouble(),
        );
      } catch (_) {}
    });
    try {
      await _editorChannel.invokeMethod<void>('style', {
        'input': input.path,
        'output': output.path,
        'settings': settings,
      });
      if (!await output.exists() || await output.length() == 0)
        throw StateError('No styled video was exported');
      onProgress(1);
      return output;
    } finally {
      timer.cancel();
    }
  }

  static Future<void> watermark(
    File input,
    File output,
    File logo,
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
      if (Platform.isAndroid || Platform.isIOS) {
        await _editorChannel.invokeMethod<void>('watermark', {
          'input': input.path,
          'output': output.path,
          'logo': logo.path,
        });
      } else if (Platform.isWindows) {
        final args = (input.path, output.path, logo.path);
        final result = await Isolate.run(() => _windowsWatermark(args));
        if (result != 0)
          throw StateError(
            result == -3
                ? 'Download cancelled'
                : 'Could not export the watermarked video.',
          );
      } else {
        throw UnsupportedError(
          'Watermarked video downloads require Android, iOS or Windows.',
        );
      }
      if (!await output.exists() || await output.length() == 0)
        throw StateError('No video was exported.');
      onProgress(1);
    } finally {
      timer.cancel();
    }
  }

  static Future<void> cancel() async {
    if (Platform.isWindows) {
      _library().lookupFunction<Void Function(), void Function()>(
        'pulse_editor_cancel',
      )();
    } else if (Platform.isAndroid || Platform.isIOS) {
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
