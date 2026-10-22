import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/admin.dart';
import '../lib/control.dart';
import '../lib/repository.dart' hide Row;

// These widget tests mock RPCs and use empty avatars. A real Supabase client
// starts asynchronous SDK resources whose disposal can stall the fake clock.
// Fail immediately if a widget accidentally reaches the real-client boundary.
class OfflineStaffClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call: ${invocation.memberName}');
}

class StaffRepository extends PulseRepository {
  StaffRepository() : super(OfflineStaffClient());
  bool verified = false, disposed = false, reject = false;
  final actions = <String>[];
  String? lastQuery;
  Completer<void>? actionGate;

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    if (name == 'admin_overview') {
      return {
        'users': 1,
        'messages': 0,
        'groups': 0,
        'channels': 0,
        'reports': [],
      };
    }
    if (name == 'control') {
      final action = params['p_action'] as String;
      if (action == 'search') {
        lastQuery = (params['p_data'] as Map)['query'] as String;
        return [
          {
            'id': 'member-id',
            'username': 'test_member',
            'display_name': 'Test Member',
            'avatar_path': null,
            'verified': verified,
            'state': 'active',
          },
        ];
      }
      actions.add(action);
      if (actionGate != null) await actionGate!.future;
      if (reject) throw StateError('Staff access required');
      verified = action == 'verify';
      return {'updated': true, 'email_queued': false};
    }
    throw StateError('Unexpected RPC: $name');
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets(
    'dashboard opens account verification and preserves shared repo',
    (tester) async {
      final repo = StaffRepository();
      await tester.pumpWidget(MaterialApp(home: AdminScreen(repo: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage user verification'));
      await tester.pumpAndSettle();
      expect(find.text('User verification'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '@test_member');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.lastQuery, 'test_member');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(repo.actions, isEmpty);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.actions, ['verify']);
      expect(repo.verified, isTrue);
      expect(find.text('Remove'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.actions, ['verify', 'unverify']);
      expect(repo.verified, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.disposed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets('server rejection does not grant a local verified badge', (
    tester,
  ) async {
    final repo = StaffRepository()..reject = true;
    await tester.pumpWidget(MaterialApp(home: PulseControl(repo: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.verified, isFalse);
    expect(repo.actions, ['verify']);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Action denied.'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });

  testWidgets('cancel sends nothing and progress waits for server work', (
    tester,
  ) async {
    final repo = StaffRepository();
    await tester.pumpWidget(MaterialApp(home: PulseControl(repo: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.actions, isEmpty);
    expect(repo.verified, isFalse);

    final gate = Completer<void>();
    repo.actionGate = gate;
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    // The server is deliberately pending, so do not wait for all animations.
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.actions, ['verify']);
    expect(repo.verified, isFalse);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final verifyButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Verify'),
    );
    expect(verifyButton.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.verified, isTrue);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
