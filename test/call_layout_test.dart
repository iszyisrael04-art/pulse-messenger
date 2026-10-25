import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/call_layout.dart';

Widget video(String name, Color color) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color, const Color(0xff071c24)],
    ),
  ),
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.person, size: 80, color: Colors.white30),
        Text(name, style: const TextStyle(color: Colors.white)),
      ],
    ),
  ),
);

PulseCallLayout call({
  VoidCallback? hangup,
  VoidCallback? mute,
  List<Widget> groups = const [],
  String? error,
  bool enabled = true,
}) => PulseCallLayout(
  name: 'Agent Fury',
  status: '00:42',
  videoCall: true,
  camera: true,
  muted: false,
  speaker: true,
  controlsEnabled: enabled,
  error: error,
  mainVideo: (_) => video('Peer camera', const Color(0xff48616e)),
  previewVideo: (_) => video('Your camera', const Color(0xff325b53)),
  groupVideos: groups,
  onHangUp: hangup ?? () {},
  onMembers: () {},
  onMute: mute ?? () {},
  onCamera: () {},
  onSwitchCamera: () {},
  onSpeaker: () {},
  onDetails: () {},
);

void main() {
  testWidgets(
    'Preview swaps, drags within safe bounds and leaves End call usable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var ended = 0, muted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: call(hangup: () => ended++, mute: () => muted++),
          ),
        ),
      );
      final preview = find.byKey(const ValueKey('call-preview'));
      expect(
        tester.getRect(find.text('Your camera')).center.dx,
        greaterThan(200),
      );
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Your camera')).center.dx,
        closeTo(180, 1),
      );
      await tester.drag(preview, const Offset(-900, -900));
      await tester.pumpAndSettle();
      final box = tester.getRect(preview);
      final dock = tester.getRect(find.byKey(const ValueKey('call-controls')));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.top, greaterThanOrEqualTo(80));
      expect(box.bottom, lessThan(dock.top));
      await tester.tap(find.byTooltip('Mute microphone'));
      await tester.tap(find.byTooltip('End call'));
      expect(muted, 1);
      expect(ended, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compact, large text and eight-person calls keep controls visible',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final size in [
        const Size(320, 568),
        const Size(800, 360),
        const Size(1024, 768),
      ]) {
        tester.view.physicalSize = size;
        for (final group in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: call(
                    groups: group
                        ? [
                            for (var i = 0; i < 8; i++)
                              ColoredBox(
                                color: i.isEven ? Colors.blueGrey : Colors.teal,
                              ),
                          ]
                        : const [],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('End call'), findsOneWidget);
          final end = tester.getRect(find.byKey(const ValueKey('call-hangup')));
          expect(end.bottom, lessThanOrEqualTo(size.height));
          expect(end.right, lessThanOrEqualTo(size.width));
          expect(
            tester.takeException(),
            isNull,
            reason: '$size / group=$group',
          );
        }
      }
    },
  );

  testWidgets(
    'More opens real view controls; disabled devices do not disable End',
    (tester) async {
      var ended = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: call(enabled: false, hangup: () => ended = true),
          ),
        ),
      );
      await tester.tap(find.byTooltip('More call options'));
      await tester.pumpAndSettle();
      expect(find.text('Participants'), findsOneWidget);
      expect(find.text('Swap video views'), findsOneWidget);
      await tester.tap(find.text('Fit whole video'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fill the screen'), findsOneWidget);
      await tester.tap(find.byTooltip('End call'));
      expect(ended, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Remote hang-up closes the call even while its options sheet is open',
    (tester) async {
      BuildContext? callContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (home) => Scaffold(
              body: TextButton(
                child: const Text('Open call'),
                onPressed: () => Navigator.push(
                  home,
                  MaterialPageRoute<void>(
                    builder: (page) => Scaffold(
                      body: Builder(
                        builder: (call) {
                          callContext = call;
                          return TextButton(
                            child: const Text('Open options'),
                            onPressed: () => showModalBottomSheet<void>(
                              context: call,
                              builder: (_) => const SizedBox(
                                height: 120,
                                child: Text('Call options sheet'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open options'));
      await tester.pumpAndSettle();
      expect(find.text('Call options sheet'), findsOneWidget);
      pulseCloseCallRoute(callContext!);
      await tester.pumpAndSettle();
      expect(find.text('Open call'), findsOneWidget);
      expect(find.text('Call options sheet'), findsNothing);
      expect(find.text('Open options'), findsNothing);
    },
  );

  testWidgets(
    'Call surface visual review uses synthetic camera placeholders only',
    (tester) async {
      if (Platform.environment['GITHUB_ACTIONS'] != 'true' ||
          Platform.environment['RUNNER_OS'] != 'Linux')
        return;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      final shots = <ui.Image>[];
      final key = GlobalKey();
      for (final size in [const Size(360, 780), const Size(800, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(key: key, child: call()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image = await tester.runAsync(
          () =>
              (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
                  .toImage(pixelRatio: .5),
        );
        shots.add(image!);
      }
      final sheet = ui.PictureRecorder();
      final c = Canvas(sheet);
      c.drawRect(
        const Rect.fromLTWH(0, 0, 400, 570),
        Paint()..color = Colors.black,
      );
      c.drawImage(shots[0], Offset.zero, Paint());
      c.drawImage(shots[1], const Offset(0, 390), Paint());
      final picture = sheet.endRecording();
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(400, 570);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final b64 = base64Encode(bytes!);
      for (var i = 0; i < b64.length; i += 8000) {
        print(
          'PULSE_CALL_PREVIEW:${i ~/ 8000}:${b64.substring(i, (i + 8000).clamp(0, b64.length))}',
        );
      }
      picture.dispose();
      for (final image in shots) {
        image.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
