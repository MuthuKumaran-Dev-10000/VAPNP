import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color background = Color(0xff090d16); 
  static const Color surface = Color(0xff121824);    
  static const Color border = Color(0xff1f293d);     
  static const Color textPrimary = Color(0xfff8fafc); 
  static const Color textSecondary = Color(0xff94a3b8); 
  static const Color textMuted = Color(0xff64748b);     

  static const Color primary = Color(0xff10b981);   // Emerald (Success)
  static const Color secondary = Color(0xff3b82f6); // Neon Blue
  static const Color accent = Color(0xfff59e0b);    // Amber (Warning / Selected Pin)
  static const Color danger = Color(0xffef4444);    // Red (Delete/Error)

  static ThemeData get themeData {
    final baseTheme = ThemeData.dark();
    return baseTheme.copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: danger,
      ),
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.outfit(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: const TextStyle(color: textSecondary, fontSize: 13),
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
  }
}
