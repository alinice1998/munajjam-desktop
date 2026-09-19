import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Dark Background Palette
  static const Color background = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF050D1A);
  static const Color surfaceCard = Color(0xFF0A1628);
  static const Color glassBackground = Color(0xCC0F172A);
  static const Color glassCard = Color(0x991E293B);
  static const Color glassBorder = Color(0x26FFFFFF);
  static const Color glassHover = Color(0x1AFFFFFF);

  // Accents & Gradients
  static const Color primaryEmerald = Color(0xFF10B981);
  static const Color primaryTeal = Color(0xFF14B8A6);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentGold = Color(0xFFF59E0B);
  static const Color warningAmber = Color(0xFFEAB308);
  static const Color dangerRed = Color(0xFFEF4444);

  // Similarity Score Colors
  static const Color scoreHigh = Color(0xFF22C55E);   // >= 95%
  static const Color scoreMed = Color(0xFFEAB308);    // >= 90%
  static const Color scoreLow = Color(0xFFEF4444);    // < 90%

  // Waveform Region Colors
  static const Color regionHigh = Color(0x5922C55E);
  static const Color regionMed = Color(0x59EAB308);
  static const Color regionLow = Color(0x59EF4444);
  static const Color regionSelected = Color(0x8014B8A6);
  static const Color playhead = Color(0xFF10B981);

  // Repetition Colors (Waqf & Ibtida' / Retake)
  static const Color repetitionPurple = Color(0xFF8B5CF6);
  static const Color repetitionRegion = Color(0x668B5CF6);
  static const Color repetitionBadgeBg = Color(0x338B5CF6);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color textMuted = Color(0x66FFFFFF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryEmerald,
        secondary: AppColors.primaryTeal,
        surface: AppColors.surfaceCard,
        error: AppColors.dangerRed,
      ),
      textTheme: GoogleFonts.tajawalTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.amiri(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        displayMedium: GoogleFonts.amiri(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.tajawal(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.tajawal(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.tajawal(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.tajawal(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        bodySmall: GoogleFonts.tajawal(
          fontSize: 11,
          color: AppColors.textMuted,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.glassCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        elevation: 0,
      ),
    );
  }
}
