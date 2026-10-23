import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/presence.dart';
import 'presence_offline.dart' as rules;

void main() {
  test('presence labels and expiry bounds', rules.main);
  testWidgets('background update follows an in-flight foreground heartbeat', (
    tester,
  ) async {
    final gate = Completer<dynamic>();
    final updates = <Map<String, dynamic>>[];
    final presence = PulsePresence(
      owner: () => 'owner',
      peers: () => [],
      rpc: (name, data) async {
        if (name == 'presence_tick') {
          updates.add(Map<String, dynamic>.from(data));
          if (updates.length == 1) return gate.future;
          return {'sharing': true};
        }
        return [];
      },
    );
    presence.start();
    presence.didChangeAppLifecycleState(AppLifecycleState.paused);
    gate.complete({'sharing': true});
    await tester.pump();
    await tester.pump();
    expect(updates.map((u) => u['p_active']), [true, false]);
    expect(
      updates[1]['p_sequence'],
      greaterThan(updates[0]['p_sequence'] as int),
    );
    expect(presence.statuses, isEmpty);
    presence.dispose();
    await tester.pump();
  });
  testWidgets(
    'an older heartbeat response cannot undo a saved privacy choice',
    (tester) async {
      final gate = Completer<dynamic>();
      var first = true;
      final presence = PulsePresence(
        owner: () => 'owner',
        peers: () => [],
        rpc: (name, data) async {
          if (name == 'presence_sharing') return null;
          if (name == 'presence_tick') {
            if (first) {
              first = false;
              return gate.future;
            }
            return {'sharing': false};
          }
          return [];
        },
      );
      presence.start();
      await presence.setSharing(false);
      gate.complete({'sharing': true});
      await tester.pump();
      await tester.pump();
      expect(presence.sharing, false);
      presence.dispose();
      await tester.pump();
    },
  );
}
