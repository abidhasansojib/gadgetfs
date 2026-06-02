import 'package:flutter/material.dart';

ThemeData buildLightTheme({ColorScheme? dynamicScheme}) {
  final base = dynamicScheme != null
      ? ThemeData(useMaterial3: true, colorScheme: dynamicScheme)
      : ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        );
  final cs = base.colorScheme;
  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(centerTitle: false, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: cs.outlineVariant.withOpacity(0.5), thickness: 1),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.primary, width: 2)),
    ),
  );
}

ThemeData buildDarkTheme({ColorScheme? dynamicScheme}) {
  final base = dynamicScheme != null
      ? ThemeData(useMaterial3: true, colorScheme: dynamicScheme)
      : ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF4F46E5),
          brightness: Brightness.dark,
        );
  final cs = base.colorScheme;
  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(centerTitle: false, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: cs.outlineVariant.withOpacity(0.5), thickness: 1),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.primary, width: 2)),
    ),
  );
}
