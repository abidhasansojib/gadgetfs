import 'package:flutter/material.dart';

import '../../../core/models/gadget_status.dart';

class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.status});
  final GadgetStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget pill({required IconData icon, required String label, required bool ok, String? detail}) {
      final bg = ok ? cs.secondaryContainer : cs.errorContainer;
      final fg = ok ? cs.onSecondaryContainer : cs.onErrorContainer;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(detail, style: TextStyle(color: fg)),
            ],
          ],
        ),
      );
    }

    final udcOk = status.udcList.isNotEmpty;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        pill(icon: Icons.admin_panel_settings_outlined, label: 'Root', ok: status.rootAvailable),
        pill(icon: Icons.usb_outlined, label: 'Support', ok: status.supportAvailable),
        pill(icon: Icons.hub_outlined, label: 'UDC', ok: udcOk, detail: udcOk ? status.udcList.first : 'Not found'),
        pill(icon: status.isActive ? Icons.check_circle_outline : Icons.radio_button_unchecked, label: status.state, ok: !status.isError),
      ],
    );
  }
}
