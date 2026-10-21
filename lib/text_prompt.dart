import 'package:flutter/material.dart';

Future<String?> showPulseTextPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 500,
  int minLines = 1,
  int maxLines = 3,
  bool allowEmpty = false,
  String actionLabel = 'Save',
  String? helperText,
  TextInputType? keyboardType,
  String? Function(String)? validator,
}) => showDialog<String>(
  context: context,
  builder: (_) => PulseTextPrompt(
    title: title,
    initial: initial,
    maxLength: maxLength,
    minLines: minLines,
    maxLines: maxLines,
    allowEmpty: allowEmpty,
    actionLabel: actionLabel,
    helperText: helperText,
    keyboardType: keyboardType,
    validator: validator,
  ),
);

/// The controller lives exactly as long as the route's TextField, including
/// the reverse animation after Navigator.pop completes its result future.
class PulseTextPrompt extends StatefulWidget {
  const PulseTextPrompt({
    super.key,
    required this.title,
    this.initial = '',
    this.maxLength = 500,
    this.minLines = 1,
    this.maxLines = 3,
    this.allowEmpty = false,
    this.actionLabel = 'Save',
    this.helperText,
    this.keyboardType,
    this.validator,
  });
  final String title, initial;
  final int maxLength, minLines, maxLines;
  final bool allowEmpty;
  final String actionLabel;
  final String? helperText;
  final TextInputType? keyboardType;
  final String? Function(String)? validator;
  @override
  State<PulseTextPrompt> createState() => _PulseTextPromptState();
}

class _PulseTextPromptState extends State<PulseTextPrompt> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        helperText: widget.helperText,
        errorText: widget.validator?.call(controller.text.trim()),
      ),
      autofocus: true,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            (widget.allowEmpty || controller.text.trim().isNotEmpty) &&
                widget.validator?.call(controller.text.trim()) == null
            ? () => Navigator.pop(context, controller.text.trim())
            : null,
        child: Text(widget.actionLabel),
      ),
    ],
  );
}
