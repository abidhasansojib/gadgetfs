import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../shared/theme.dart';
import 'theme_mode_provider.dart';
import 'dynamic_color_provider.dart';

class GadgetFsApp extends ConsumerWidget {
  const GadgetFsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final useDynamic = ref.watch(dynamicColorsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final light = useDynamic ? lightDynamic : null;
        final dark = useDynamic ? darkDynamic : null;
        return MaterialApp.router(
          title: 'GadgetFS',
          theme: buildLightTheme(dynamicScheme: light),
          darkTheme: buildDarkTheme(dynamicScheme: dark),
          themeMode: themeMode,
          routerConfig: router,
        );
      },
    );
  }
}
