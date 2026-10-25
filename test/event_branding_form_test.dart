import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/event_branding_form.dart';

void main() {
  testWidgets('Branding validates before save and waits for server approval', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PulseEventBrandingForm(
          currentLogo: const Icon(Icons.photo),
          chooseImage: () async => PulseBrandImage(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGPUWtDEwMDAxMDAwMDAAAAPYgFQ5XMZVAAAAABJRU5ErkJggg==',
            ),
            'png',
            'image/png',
          ),
          save: (image, title, days) {
            calls++;
            return pending.future;
          },
          restore: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Save event icon'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Enter an event name.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Eid');
    await tester.tap(find.text('Choose event image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-icon-preview')), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '0');
    await tester.tap(find.text('Save event icon'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Choose 1 to 90 days.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '7');
    await tester.tap(find.text('Save event icon'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.completeError(StateError('Administrator required'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save the icon.'), findsOneWidget);
    expect(find.textContaining('Event icon saved.'), findsNothing);
  });
  testWidgets('Restore failures are visible and the action can be retried', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PulseEventBrandingForm(
          currentLogo: const Icon(Icons.photo),
          chooseImage: () async => null,
          save: (image, title, days) async {},
          restore: () async => throw StateError('Connection unavailable'),
        ),
      ),
    );
    await tester.tap(find.text('Restore original Pulse logo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection unavailable'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });
}
