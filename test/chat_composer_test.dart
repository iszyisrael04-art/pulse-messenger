import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/chat_composer.dart';

void main() {
  testWidgets('Enter sends once; Shift+Enter inserts a newline at the cursor', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Hello');
    addTearDown(controller.dispose);
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseChatComposer(
            controller: controller,
            onSend: () => sends++,
            onAttach: () {},
            onVoice: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 1);
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.text, 'He\nllo');
    expect(sends, 1);
  });

  testWidgets('IME composition and empty messages do not send', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseChatComposer(
            controller: controller,
            onSend: () => sends++,
            onAttach: () {},
            onVoice: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 0);
    controller.value = const TextEditingValue(
      text: 'word',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 0);
  });

  testWidgets('mobile send action works and microphone is inside the field', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Mobile message');
    addTearDown(controller.dispose);
    var sends = 0, recordings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PulseChatComposer(
                controller: controller,
                onSend: () => sends++,
                onAttach: () {},
                onVoice: () => recordings++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sends, 1);
    final microphone = find.descendant(
      of: find.byType(TextField),
      matching: find.byTooltip('Record voice note'),
    );
    expect(microphone, findsOneWidget);
    await tester.tap(microphone);
    expect(recordings, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy composer blocks send, attachments and recording', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Pending');
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseChatComposer(
            controller: controller,
            busy: true,
            onSend: () => calls++,
            onAttach: () => calls++,
            onVoice: () => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 0);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.mic_none_rounded),
          )
          .onPressed,
      isNull,
    );
  });
}
