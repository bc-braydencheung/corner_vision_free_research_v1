import 'package:flutter/material.dart';

const Color kVoid = Color(0xFF07070C);
const Color kSurface = Color(0xFF12121C);
const Color kSurfaceAlt = Color(0xFF1A1A28);
const Color kAccent = Color(0xFF6EE7F9);
const Color kAccentWarm = Color(0xFFF6C36B);
const Color kDanger = Color(0xFFFF6B6B);
const Color kMuted = Color(0xFF8C8CA6);

ThemeData buildLabTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kVoid,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      secondary: kAccentWarm,
      surface: kSurface,
      error: kDanger,
    ),
    cardTheme: const CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: const Color(0xFFE6E6F0),
      displayColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF23233A), space: 1),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kAccent,
      thumbColor: kAccent,
      inactiveTrackColor: kSurfaceAlt,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: kSurface,
      indicatorColor: Color(0xFF23334A),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: Color(0xFF23334A),
    ),
  );
}

const TextStyle kMonoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: <String>['Courier New', 'monospace'],
  height: 1.35,
);
