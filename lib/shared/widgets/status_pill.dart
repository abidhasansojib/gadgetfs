import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final bool ok;
  final String? subtitle;

  const StatusPill({
    super.key,
    required this.label,
    required this.ok,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = ok ? scheme.primaryContainer : scheme.errorContainer;
    final fg = ok ? scheme.onPrimaryContainer : scheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(subtitle!, style: TextStyle(color: fg.withOpacity(0.85))),
          ],
        ],
      ),
    );
  }
}
