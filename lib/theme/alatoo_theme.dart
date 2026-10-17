import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette sampled from alatoo.edu.kg.
class AlatooColors {
  static const navy = Color(0xFF001F5B);
  static const navy2 = Color(0xFF19316A);
  static const crimson = Color(0xFFC70017);
  static const ink = Color(0xFF1F1F1F);
  static const mist = Color(0xFFF7F8FA);
  static const line = Color(0xFFE5E5E5);

  /// Cockpit surfaces: the flight screen stays dark so the video feed reads well.
  static const deep = Color(0xFF00102E);
  static const panel = Color(0xFF0A1F46);
  static const ok = Color(0xFF2ECC71);
  static const warn = Color(0xFFF2B01E);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, navy2],
  );
}

class AlatooTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AlatooColors.navy,
        primary: AlatooColors.navy,
        secondary: AlatooColors.crimson,
        surface: Colors.white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AlatooColors.mist,
    );

    return base.copyWith(
      textTheme: _text(base.textTheme, AlatooColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AlatooColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AlatooColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AlatooColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AlatooColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AlatooColors.line),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AlatooColors.navy : null,
        ),
      ),
    );
  }

  /// Styles are applied one by one rather than through
  /// `GoogleFonts.interTextTheme`, whose return type comes from the package's
  /// own Material fork and does not match Flutter's [TextTheme].
  static TextTheme _text(TextTheme base, Color color) {
    TextStyle? inter(TextStyle? s) => s == null
        ? null
        : GoogleFonts.inter(textStyle: s).copyWith(color: color);
    TextStyle poppins(double size, FontWeight weight) =>
        GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

    return base
        .copyWith(
          bodyLarge: inter(base.bodyLarge),
          bodyMedium: inter(base.bodyMedium),
          bodySmall: inter(base.bodySmall),
          labelMedium: inter(base.labelMedium),
          labelSmall: inter(base.labelSmall),
          titleSmall: inter(base.titleSmall),
        )
        .copyWith(
          displaySmall: poppins(30, FontWeight.w700),
          headlineSmall: poppins(22, FontWeight.w700),
          titleMedium: poppins(16, FontWeight.w600),
          labelLarge: poppins(14, FontWeight.w600),
        );
  }
}
