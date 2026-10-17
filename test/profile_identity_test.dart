import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/avatar.dart';
import 'package:pulse_messenger/privacy_policy.dart';

void main() {
  testWidgets('Agreement starts unchecked and opens the actual policy', (
    tester,
  ) async {
    bool agreed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => PulsePrivacyAgreement(
              accepted: agreed,
              onChanged: (v) => set(() => agreed = v),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    await tester.tap(find.text('Read Privacy Policy'));
    await tester.pumpAndSettle();
    expect(find.text(pulsePrivacyText), findsOneWidget);
    Navigator.of(tester.element(find.byType(PulsePrivacyPage))).pop();
    await tester.pumpAndSettle();
    expect(agreed, false);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(agreed, true);
  });
  testWidgets(
    'Missing and broken portraits display a photo icon without initials',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 80,
              child: PulsePhotoPlaceholder(),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 80,
              child: PulsePortrait(
                provider: MemoryImage(Uint8List.fromList([1, 2, 3])),
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
