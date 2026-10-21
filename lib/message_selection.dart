import 'package:flutter/material.dart';

/// Single-message actions. Copy never sends a message or copies a private URL.
class PulseMessageSelection extends StatelessWidget {
  const PulseMessageSelection({
    super.key,
    required this.canCopy,
    required this.canReact,
    required this.onClose,
    required this.onAction,
    required this.onDelete,
  });

  final bool canCopy, canReact;
  final VoidCallback onClose, onDelete;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SafeArea(
      top: false,
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Cancel selection',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
              const Expanded(child: Text('1 selected', maxLines: 1)),
              if (canReact)
                IconButton(
                  tooltip: 'Reply',
                  onPressed: () => onAction('reply'),
                  icon: const Icon(Icons.reply_rounded),
                ),
              IconButton(
                tooltip: 'Copy text',
                onPressed: canCopy ? () => onAction('copy') : null,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: 'Delete message',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              if (canReact)
                PopupMenuButton<String>(
                  tooltip: 'More message actions',
                  onSelected: onAction,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'star', child: Text('Star / unstar')),
                  ],
                ),
            ],
          ),
          if (canReact)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                    IconButton(
                      tooltip: 'React $emoji',
                      onPressed: () => onAction('react:$emoji'),
                      icon: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
