import 'package:flutter/material.dart';

ThemeData meowWatchTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFFEFB38C),
    onPrimary: Color(0xFF332318),
    secondary: Color(0xFFB9A9D3),
    onSecondary: Color(0xFF251E33),
    surface: Color(0xFF10141F),
    onSurface: Color(0xFFF5EDE0),
    onSurfaceVariant: Color(0xFFBDBDCA),
    surfaceContainer: Color(0xFF1A2232),
    surfaceContainerHighest: Color(0xFF263045),
    outline: Color(0xFF8791A5),
    outlineVariant: Color(0xFF333F52),
    error: Color(0xFFFFB4AB),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'DMSans',
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontFamily: 'DMSerifDisplay',
        fontSize: 58,
        height: 1.08,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontFamily: 'DMSerifDisplay',
        fontSize: 44,
        height: 1.12,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontFamily: 'DMSerifDisplay',
        fontSize: 34,
        height: 1.15,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: 'DMSerifDisplay',
        fontSize: 28,
        height: 1.2,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: 'DMSans',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalBarrierColor: Colors.black54,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
  );
}
