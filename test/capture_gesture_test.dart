import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/chat_camera.dart';
import 'phone_rules_offline.dart' as phone;
import 'interests_offline.dart' as interests;
import 'edit_history_offline.dart' as edits;

void main() {
  test('phone and interest rules', () {
    phone.main();
    interests.main();
    edits.main();
  });
  testWidgets('camera tap and hold/swipe use separate actions', (tester) async {
    final actions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PulseCameraButton(enabled: true, onOpen: actions.add),
          ),
        ),
      ),
    );
    final target = find.byType(PulseCameraButton);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(actions, [false]);
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(actions, [false, true]);
  });
}
