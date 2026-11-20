import 'package:flutter/material.dart';

/// Colours from the mockups. No red anywhere: problems are shown in gold with an icon.
class C {
  static const bg = Color(0xFF0F1418);
  static const card = Color(0xFF182129);
  static const card2 = Color(0xFF202C36);
  static const line = Color(0xFF2C3A46);
  static const text = Color(0xFFE8EEF2);
  static const dim = Color(0xFF93A4B1);
  static const teal = Color(0xFF2EC4B6);
  static const onTeal = Color(0xFF062A27);
  static const gold = Color(0xFFF2C14E);
  static const green = Color(0xFF7BD389);
  static const navy = Color(0xFF1D3557);
  static const sky = Color(0xFF8ECAE6);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.teal,
    onPrimary: C.onTeal,
    secondary: C.gold,
    onSecondary: Color(0xFF2A1F00),
    surface: C.bg,
    onSurface: C.text,
    surfaceContainerHighest: C.card2,
    surfaceContainerHigh: C.card,
    surfaceContainer: C.card,
    outline: C.line,
    error: C.gold,
    onError: Color(0xFF2A1F00),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    cardTheme: const CardThemeData(color: C.card, elevation: 0, margin: EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, foregroundColor: C.text, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.card,
      indicatorColor: C.teal.withValues(alpha: .22),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: C.text, side: const BorderSide(color: C.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: C.card2,
      selectedColor: C.teal,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 14),
      checkmarkColor: C.onTeal,
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.card2, contentTextStyle: TextStyle(color: C.text), behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(filled: true, fillColor: C.card2, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10)))),
    dividerTheme: const DividerThemeData(color: C.line),
  );
}
