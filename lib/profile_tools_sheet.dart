import 'package:flutter/material.dart';

class PulseProfileTool {
  const PulseProfileTool(this.title, this.subtitle, this.icon, this.onTap);
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
}

class PulseProfileToolGroup {
  const PulseProfileToolGroup(this.title, this.tools);
  final String title;
  final List<PulseProfileTool> tools;
}

class PulseProfileToolsSheet extends StatelessWidget {
  const PulseProfileToolsSheet({super.key, required this.groups});
  final List<PulseProfileToolGroup> groups;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      minChildSize: .45,
      maxChildSize: .94,
      builder: (context, scroll) => SafeArea(
        top: false,
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Profile tools',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Close profile tools',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Make it yours. Manage who sees your content.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                child: Text(
                  group.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < group.tools.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 76,
                          endIndent: 16,
                          color: colors.outlineVariant.withValues(alpha: .4),
                        ),
                      ListTile(
                        enabled: group.tools[i].onTap != null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            group.tools[i].icon,
                            color: colors.primary,
                            size: 23,
                          ),
                        ),
                        title: Text(
                          group.tools[i].title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            group.tools[i].subtitle,
                            style: const TextStyle(fontSize: 12, height: 1.35),
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                          size: 21,
                        ),
                        onTap: group.tools[i].onTap,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
