import 'package:flutter/material.dart';

const kNavy = Color(0xFF05091C);
const kCyan = Color(0xFF35D5F2);
const kBlue = Color(0xFF397BFF);
const kPurple = Color(0xFF8050E8);
const kBrandGradient = LinearGradient(
    colors: [kCyan, kPurple], begin: Alignment.topLeft, end: Alignment.bottomRight);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: kCyan,
    onPrimary: kNavy,
    secondary: kPurple,
    tertiary: kBlue,
    surface: Color(0xFF0B1230),
    onSurface: Colors.white,
    surfaceContainerHighest: Color(0xFF16204A),
    primaryContainer: Color(0xFF123A5A),
    onPrimaryContainer: Colors.white,
    error: Color(0xFFFF8A80),
    errorContainer: Color(0xFF4A1A24),
    onErrorContainer: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kNavy,
    appBarTheme: const AppBarTheme(
        backgroundColor: kNavy, elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: const Color(0xFF0B1230)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
  );
}