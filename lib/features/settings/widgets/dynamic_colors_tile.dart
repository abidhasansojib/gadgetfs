import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/dynamic_color_provider.dart';

class DynamicColorsTile extends ConsumerWidget {
  const DynamicColorsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useDynamic = ref.watch(dynamicColorsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.palette_rounded, color: cs.primary),
      title: const Text('Use dynamic colors'),
      subtitle: Text(
        Platform.isAndroid
            ? 'Match the system Material You palette on supported devices (Android 12+).'
            : 'Dynamic colors are only available on Android 12+. Other platforms use the app palette.',
      ),
      trailing: Switch.adaptive(
        value: useDynamic,
        onChanged: (v) async {
          await ref.read(dynamicColorsProvider.notifier).setEnabled(v);
          HapticFeedback.selectionClick();
        },
      ),
    );
  }
}
