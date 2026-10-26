import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/chat_preview_line.dart';
import '../lib/chat_display.dart';

void main() {
  testWidgets('Latest text and accurate outgoing receipt fit a compact row', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 240, child: PulseChatPreviewLine(
      owner: 'me', message: {'sender_id': 'me', 'created_at': '2026-10-26T12:00:00Z', 'body': 'How was your day? A very long message', 'delivery': 'read'},
    )))));
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.textContaining('You:'), findsNothing);
    expect(find.textContaining('How was your day?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Incoming group previews identify the sender without outgoing ticks', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PulseChatPreviewLine(
      owner: 'me', group: true, message: {'sender_id':'friend','sender_name':'Danny','body':'Hello','created_at':'2026-10-26T12:00:00Z'},
    )))));
    expect(find.text('Danny: Hello'), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });
  test('No fabricated delivered or read state for cached summaries', () {
    expect(pulseChatDelivery(null, 'me'), isNull);
    expect(pulseChatDelivery({'sender_id':'friend','created_at':'now'}, 'me'), isNull);
    expect(pulseChatDelivery({'sender_id':'me','created_at':'now'}, 'me'), 'sent');
  });
}
