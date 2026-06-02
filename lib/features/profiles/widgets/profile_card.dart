import 'package:flutter/material.dart';

import '../../../core/models/gadget_profile.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final GadgetProfile profile;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final vid = profile.vendorId.toRadixString(16).padLeft(4, '0').toUpperCase();
    final pid = profile.productId.toRadixString(16).padLeft(4, '0').toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(profile.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isSelected)
                  Chip(
                    label: const Text('Selected'),
                    avatar: const Icon(Icons.check, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${profile.roleType.label} • VID:0x$vid PID:0x$pid', style: Theme.of(context).textTheme.bodySmall),
            if (profile.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(profile.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.playlist_add_check_outlined),
                    label: const Text('Select'),
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'duplicate':
                        onDuplicate();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
