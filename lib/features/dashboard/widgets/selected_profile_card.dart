import 'package:flutter/material.dart';
import '../../../core/models/gadget_profile.dart';

enum ProfileCardLayout { compact, expanded }

class SelectedProfileCard extends StatelessWidget {
  const SelectedProfileCard({
    super.key,
    required this.profile,
    this.layout = ProfileCardLayout.expanded,
    this.isActive = false,
    this.isSelected = false,
    this.onTap,
    this.onEmptyTap,
    this.trailing,
    this.showDescription = true,
    this.showSerial = false,
    this.emptyTitle = 'No profile selected',
    this.emptySubtitle = 'Create or select a profile to activate a gadget role.',
  });

  final GadgetProfile? profile;

  /// compact: for lists (Profiles screen)
  /// expanded: for home header/details
  final ProfileCardLayout layout;

  /// Badge state
  final bool isActive;
  final bool isSelected;

  /// Taps
  final VoidCallback? onTap;
  final VoidCallback? onEmptyTap;

  /// Optional trailing widget (menu button, chevron, etc.)
  final Widget? trailing;

  /// Display toggles
  final bool showDescription;
  final bool showSerial;

  /// Empty state copy
  final String emptyTitle;
  final String emptySubtitle;

  static String fmtHex4(int v) =>
      '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  static String _cleanOrDash(String s) {
    final t = s.trim();
    return t.isEmpty ? '—' : t;
  }

  String _roleLabel(GadgetRoleType t) {
    // Your enum does not expose `.label`, so keep a local mapping.
    switch (t) {
      case GadgetRoleType.mouse:
        return 'Mouse';
      case GadgetRoleType.keyboard:
        return 'Keyboard';
      case GadgetRoleType.composite:
        return 'Composite';
    }
  }

  IconData _roleIcon(GadgetRoleType t) {
    switch (t) {
      case GadgetRoleType.mouse:
        return Icons.mouse_outlined;
      case GadgetRoleType.keyboard:
        return Icons.keyboard_outlined;
      case GadgetRoleType.composite:
        return Icons.usb_outlined;
    }
  }

  Widget? _buildBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isActive) {
      return Chip(
        avatar: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Active'),
        side: BorderSide(color: cs.primaryContainer),
        backgroundColor: cs.primaryContainer,
      );
    }

    if (isSelected) {
      return Chip(
        avatar: const Icon(Icons.radio_button_unchecked, size: 18),
        label: const Text('Selected'),
        side: BorderSide(color: cs.secondaryContainer),
        backgroundColor: cs.secondaryContainer,
      );
    }

    return null;
  }

  Widget? _composeTrailingWithBadge(BuildContext context) {
    final badge = _buildBadge(context);
    if (badge == null && trailing == null) return null;

    if (badge != null && trailing != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          const SizedBox(width: 8),
          trailing!,
        ],
      );
    }

    return trailing ?? badge;
  }

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.tune),
          title: Text(emptyTitle),
          subtitle: Text(emptySubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onEmptyTap,
        ),
      );
    }

    final p = profile!;
    final vid = fmtHex4(p.vendorId);
    final pid = fmtHex4(p.productId);
    final role = _roleLabel(p.roleType);
    final manu = _cleanOrDash(p.manufacturer);
    final prod = _cleanOrDash(p.product);
    final sn = _cleanOrDash(p.serialNumber);
    final composedTrailing = _composeTrailingWithBadge(context);

    if (layout == ProfileCardLayout.compact) {
      return Card(
        child: ListTile(
          leading: Icon(_roleIcon(p.roleType)),
          title: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$role • VID $vid • PID $pid'),
              Text(
                '$manu • $prod',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: composedTrailing,
          onTap: onTap,
        ),
      );
    }

    // Expanded layout
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_roleIcon(p.roleType)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (composedTrailing != null) ...[
                    const SizedBox(width: 8),
                    composedTrailing,
                  ],
                ],
              ),

              if (showDescription) ...[
                const SizedBox(height: 8),
                Text(
                  p.description.trim().isEmpty ? '—' : p.description.trim(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Text(
                'Current identity',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),

              _KeyValueRow(k: 'Role', v: role),
              _KeyValueRow(k: 'VID', v: vid),
              _KeyValueRow(k: 'PID', v: pid),
              _KeyValueRow(k: 'Manufacturer', v: manu),
              _KeyValueRow(k: 'Product', v: prod),
              if (showSerial) _KeyValueRow(k: 'Serial', v: sn),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.k, required this.v});

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(k, style: labelStyle)),
          Expanded(child: SelectableText(v, style: valueStyle)),
        ],
      ),
    );
  }
}
