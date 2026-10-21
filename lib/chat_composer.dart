import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_camera.dart';

/// One expanding message field with attachments and recording inside its border.
class PulseChatComposer extends StatelessWidget {
  const PulseChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onVoice,
    this.onCamera,
    this.enabled = true,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend, onAttach, onVoice;
  final bool enabled, busy;
  final ValueChanged<bool>? onCamera;

  bool get composing =>
      controller.value.composing.isValid &&
      !controller.value.composing.isCollapsed;

  void submit() {
    if (enabled && !busy && !composing && controller.text.trim().isNotEmpty) {
      onSend();
    }
  }

  void newline() {
    if (!enabled || busy || composing || controller.text.length >= 8000) return;
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  includeRepeats: false,
                ): submit,
                const SingleActivator(
                  LogicalKeyboardKey.numpadEnter,
                  includeRepeats: false,
                ): submit,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    newline,
                const SingleActivator(
                  LogicalKeyboardKey.numpadEnter,
                  shift: true,
                ): newline,
              },
              child: TextField(
                controller: controller,
                enabled: enabled,
                readOnly: busy,
                minLines: 1,
                maxLines: 5,
                maxLength: 8000,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                onEditingComplete: () {},
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  counterText: '',
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: IconButton(
                    tooltip: 'Attach file, image or video',
                    onPressed: enabled && !busy ? onAttach : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulseCameraButton(
                        enabled: enabled && !busy && onCamera != null,
                        onOpen: (note) => onCamera?.call(note),
                      ),
                      IconButton(
                        tooltip: 'Record voice note',
                        onPressed: enabled && !busy ? onVoice : null,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.trim().isEmpty && !busy
                ? const SizedBox.shrink()
                : SizedBox.square(
                    dimension: 48,
                    child: IconButton.filled(
                      tooltip: 'Send message',
                      onPressed:
                          enabled && !busy && value.text.trim().isNotEmpty
                          ? submit
                          : null,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
