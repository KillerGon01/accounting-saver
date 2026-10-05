import 'package:flutter/material.dart';

const _seedColor = Color(0xFF00695C);

abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [
        FinanceColors(
          income: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
          expense: colorScheme.error,
        ),
      ],
      textTheme: base.textTheme.copyWith(
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
      ),
    );
  }
}

class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({required this.income, required this.expense});

  final Color income;
  final Color expense;

  @override
  FinanceColors copyWith({Color? income, Color? expense}) {
    return FinanceColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
    );
  }

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
    );
  }
}
