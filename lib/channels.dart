trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if ((widget.updates?.counts[c['id']] ?? 0) > 0)
      Badge(
        label: Text(
          (widget.updates!.counts[c['id']] ?? 0) > 99
              ? '99+'
              : '${widget.updates!.counts[c['id']]}',
        ),
        child: const Icon(Icons.campaign_outlined),
      ),
    const SizedBox(width: 8),
    Icon(
      followed ? Icons.check_circle : Icons.chevron_right,
      color: Theme.of(context).colorScheme.primary,
    ),
  ],
),
subtitle: Text(
  '${widget.repo.followers.where((f) => f['channel_id'] == c['id']).length} followers · ${c['description']}',
),
