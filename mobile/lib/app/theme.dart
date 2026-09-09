import 'package:flutter/material.dart';

ThemeData buildZedBizTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF176B3A));
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF7F9F7),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  );
}
