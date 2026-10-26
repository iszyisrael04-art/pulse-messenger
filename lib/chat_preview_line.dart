import 'package:flutter/material.dart';
import 'chat_display.dart';

class PulseChatPreviewLine extends StatelessWidget {
  const PulseChatPreviewLine({super.key, required this.message, required this.owner, this.group = false, this.senderName, this.unread = false});
  final Map? message;
  final String owner;
  final bool group, unread;
  final String? senderName;
  @override
  Widget build(BuildContext context) {
    final delivery = pulseChatDelivery(message, owner);
    final text = pulseChatPreview(message, owner, senderName: group ? (message?['sender_name']?.toString() ?? senderName) : null, showOwnLabel: group);
    final color = unread ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        if (delivery != null) ...[
          Semantics(
            label: delivery == 'read' ? 'Read' : delivery == 'delivered' ? 'Delivered' : 'Sent',
            child: Icon(delivery == 'sent' ? Icons.done : Icons.done_all, size: 18, color: delivery == 'read' ? Colors.lightBlue : color),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(height: 1.6, fontSize: 14, color: color, fontWeight: unread ? FontWeight.w600 : FontWeight.normal)),
        ),
      ],
    );
  }
}
