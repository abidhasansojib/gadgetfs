import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../dashboard/widgets/selected_profile_card.dart';
import '../../core/models/gadget_profile.dart';
import '../../core/storage/providers.dart';
import '../../shared/widgets/section_card.dart';

class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final selectedId = ref.watch(selectedProfileIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          IconButton(
            tooltip: 'Create',
            onPressed: () => context.go('/profiles/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: profilesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Failed to load profiles: $e')),
          data: (profiles) {
            final filtered = profiles.where((p) {
              final q = _query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return p.name.toLowerCase().contains(q) ||
                  p.description.toLowerCase().contains(q) ||
                  gadgetRoleTypeToString(p.roleType).contains(q);
            }).toList();

            filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SectionCard(
                  child: TextField(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(height: 12),
                for (final p in filtered)
                  SelectedProfileCard(
                    profile: p,
                    layout: ProfileCardLayout.compact,
                    isSelected: p.id == selectedId,
                    onTap: () => context.go('/profiles/${p.id}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        // keep your existing actions logic here
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'select',
                          child: Row(
                            children: [
                              Icon(p.id == selectedId ? Icons.check_circle : Icons.radio_button_unchecked),
                              const SizedBox(width: 8),
                              const Text('Select'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  final GadgetProfile profile;
  final bool selected;

  const _ProfileTile({
    required this.profile,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesCtrl = ref.read(profilesProvider.notifier);
    final selectedCtrl = ref.read(selectedProfileIdProvider.notifier);

    Future<void> duplicate() async {
      const uuid = Uuid();
      final copy = profile.copyWith(
        id: uuid.v4(),
        name: '${profile.name} (copy)',
        activateOnOpen: false,
      );
      await profilesCtrl.upsert(copy);
      await selectedCtrl.setSelected(copy.id);
      if (context.mounted) context.go('/profiles/${copy.id}');
    }

    Future<void> delete() async {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete profile?'),
              content: Text('This will delete "${profile.name}".'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;

      await profilesCtrl.delete(profile.id);
      if (selected) {
        await selectedCtrl.setSelected(null);
      }
    }

    return Card(
      child: ListTile(
        leading: Icon(
          switch (profile.roleType) {
            GadgetRoleType.mouse => Icons.mouse_outlined,
            GadgetRoleType.keyboard => Icons.keyboard_outlined,
            GadgetRoleType.composite => Icons.usb_outlined,
          },
        ),
        title: Text(profile.name),
        subtitle: Text(
          '${gadgetRoleTypeToString(profile.roleType)} • ${profile.description.isEmpty ? '—' : profile.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'select') await selectedCtrl.setSelected(profile.id);
            if (v == 'duplicate') await duplicate();
            if (v == 'delete') await delete();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'select',
              child: Row(
                children: [
                  Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked),
                  const SizedBox(width: 8),
                  const Text('Select'),
                ],
              ),
            ),
            const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        selected: selected,
        onTap: () => context.go('/profiles/${profile.id}'),
        onLongPress: () => selectedCtrl.setSelected(profile.id),
      ),
    );
  }
}
