import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hydralis design tokens — ocean style.
class AppColors {
  // Brand
  static const Color skyCyan = Color(0xFF0EA5E9);
  static const Color skyDeep = Color(0xFF0284C7);
  static const Color oceanMid = Color(0xFF1D4ED8);
  static const Color deepNavy = Color(0xFF0B1B3B);
  static const Color midnight = Color(0xFF0C1733);

  // Surfaces
  static const Color surface = Color(0xFFF6FAFE);
  static const Color surfaceAlt = Color(0xFFEDF4FB);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFEEF2F7);
  static const Color inputFill = Color(0xFFF1F5F9);

  // Ink
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF475569);
  static const Color inkSubtle = Color(0xFF94A3B8);
  static const Color inkOnDark = Colors.white;

  // Status
  static const Color safeGreen = Color(0xFF10B981);
  static const Color monitorAmber = Color(0xFFF59E0B);
  static const Color needHelpOrange = Color(0xFFF97316);
  static const Color emergencyRed = Color(0xFFEF4444);
  static const Color emergencyDeep = Color(0xFFB91C1C);
}

class AppGradients {
  static const LinearGradient ocean = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.skyCyan, AppColors.oceanMid, AppColors.deepNavy],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9), Color(0xFF0B4D8C)],
  );

  static const LinearGradient deep = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.midnight, AppColors.deepNavy],
  );

  static const LinearGradient safe = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF059669)],
  );

  static const LinearGradient warning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
  );

  static const LinearGradient danger = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF87171), Color(0xFFB91C1C)],
  );

  static const LinearGradient skyTint = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEAF4FE), Color(0xFFF8FBFF)],
  );
}

class AppShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x14082655),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x1F0B1B3B),
      blurRadius: 28,
      offset: Offset(0, 14),
      spreadRadius: -10,
    ),
  ];

  static const List<BoxShadow> glow = [
    BoxShadow(
      color: Color(0x550EA5E9),
      blurRadius: 30,
      offset: Offset(0, 18),
      spreadRadius: -12,
    ),
  ];
}

class AppRadii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppTextStyles {
  static TextStyle displayLarge = GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.5,
  );

  static TextStyle titleXL = GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    letterSpacing: -0.3,
  );

  static TextStyle titleLG = GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static TextStyle titleMD = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static TextStyle bodyLG = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
  );

  static TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.inkMuted,
  );

  static TextStyle bodyStrong = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.inkSubtle,
    letterSpacing: 0.2,
  );

  static TextStyle eyebrow = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.inkSubtle,
    letterSpacing: 1.2,
  );
}

class AppTheme {
  static SystemUiOverlayStyle get overlayLight => const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      );

  static SystemUiOverlayStyle get overlayDark => const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.skyCyan,
        primary: AppColors.skyCyan,
        onPrimary: Colors.white,
        secondary: AppColors.deepNavy,
        surface: AppColors.card,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      canvasColor: AppColors.surface,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyles.titleLG,
        systemOverlayStyle: overlayLight,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        hintStyle: GoogleFonts.inter(color: AppColors.inkSubtle, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: AppColors.inkMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.skyCyan, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.skyDeep,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.deepNavy,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.skyCyan;
          return const Color(0xFFCBD5E1);
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
