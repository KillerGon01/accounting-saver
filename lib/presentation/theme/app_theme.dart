import 'package:flutter/material.dart';

const _seedColor = Color(0xFF00695C);

abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// `AppTheme.dark()` is the only theme the app uses (`MaterialApp` in
/// `main.dart` forces `themeMode: ThemeMode.dark`): a near-black
/// background with a very subtle greenish tint, layered surfaces, a
/// teal/mint accent, and soft green/coral income/expense colors (see
/// `FinanceColors`), always accompanied by a sign or an icon, never
/// color alone. `AppTheme.light()` is kept (dead code on purpose, in
/// case light mode is picked back up later) but no `MaterialApp` in
/// the app uses it; tests that build their own `MaterialApp` with an
/// explicit `theme:` still do.
abstract final class AppTheme {
  static ThemeData light() => _buildLight();

  static ThemeData dark() => _buildDark();

  static ThemeData _buildLight() {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light);
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [
        FinanceColors(
          income: const Color(0xFF2E7D32),
          expense: colorScheme.error,
          warning: Colors.orange,
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

  /// Hand-built dark palette, not `ColorScheme.fromSeed`'s default
  /// one: it starts from the scheme derived from the seed (so
  /// `primary`, `secondary`, etc. stay coherent with each other) and
  /// overrides with `copyWith` the surfaces (near-black background
  /// with a barely perceptible greenish tint, in increasingly lighter
  /// layers) and the accents (teal/mint, soft coral instead of
  /// Material's default red). Contrast checked by hand (WCAG's
  /// relative luminance formula): `onSurface` gives more than 16:1
  /// over `surface`. `onSurfaceVariant` (the secondary labels:
  /// "Balance del mes", dates, "N movimientos"...) was raised from
  /// `#A9BDB4` to `#BFD0C8` to gain margin over the AA minimum for
  /// normal text (4.5:1): it now gives almost 12:1 over `surface`,
  /// almost 10:1 over `surfaceContainerHigh`, and more than 9:1 over
  /// the theme's lightest surface (`surfaceContainerHighest`) — the
  /// worst of the three cases still more than doubles the minimum.
  /// Just as generous for `income`, `expense`/`error`, and `warning`.
  static ThemeData _buildDark() {
    const surface = Color(0xFF0B120F);
    const surfaceContainerLowest = Color(0xFF070B09);
    const surfaceContainerLow = Color(0xFF0F1713);
    const surfaceContainer = Color(0xFF131E19);
    const surfaceContainerHigh = Color(0xFF18241E);
    const surfaceContainerHighest = Color(0xFF1E2C25);
    const onSurface = Color(0xFFE3EFE9);
    const onSurfaceVariant = Color(0xFFBFD0C8);
    const outline = Color(0xFF55675F);
    const primary = Color(0xFF4DB6AC);
    const onPrimary = Color(0xFF00201C);
    const secondary = Color(0xFF80CBC4);
    const onSecondary = Color(0xFF00201C);
    // Soft coral: also `FinanceColors.expense` (see below), so that
    // expense and "error" are the same tone, never two different reds.
    const error = Color(0xFFF2967D);
    const onError = Color(0xFF3A0A00);
    const income = Color(0xFF7DD3A8);
    const warning = Color(0xFFE0B341);

    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark).copyWith(
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      outline: outline,
      outlineVariant: surfaceContainerHigh,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: surfaceContainerHigh,
      onPrimaryContainer: onSurface,
      secondary: secondary,
      onSecondary: onSecondary,
      error: error,
      onError: onError,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    const pillShape = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      extensions: [
        FinanceColors(income: income, expense: colorScheme.error, warning: warning),
      ],
      textTheme: base.textTheme.copyWith(
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        // Small labels (e.g. "Balance del mes" and each monthly
        // report card's headers) in a muted gray, so the figure and
        // the content stand out, not the label that precedes them.
        labelLarge: base.textTheme.labelLarge?.copyWith(color: onSurfaceVariant),
        // Secondary labels (dates, "N movimientos", card footers...):
        // same muted gray as `labelLarge` and, by default, 12 px
        // instead of Material 3's default 11 px — the minimum
        // legible size for text that already has less contrast than
        // the main content. Some screens already set this same color
        // by hand with `.copyWith(color: onSurfaceVariant)`;
        // continuing to do so changes nothing (same color), so they
        // didn't need to be touched.
        bodySmall: base.textTheme.bodySmall?.copyWith(color: onSurfaceVariant, fontSize: 12),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s + 4),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pillShape,
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s + 4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pillShape),
      ),
      // `width` fixes a maximum width (and centers it: see
      // `_ScaffoldLayout` in the Flutter SDK, which computes the
      // horizontal offset only when there's an explicit width)
      // instead of taking up the full width minus the margin, so it
      // doesn't change size between screens with a narrower
      // `ConstrainedBox` than others. `insetPadding` fixed for the
      // same stability reason, though this doesn't prevent the
      // vertical "jump" the `FloatingActionButton` causes (see
      // docs/design.md, "Aviso estable al navegar"): that jump comes
      // from where the `Scaffold` positions the notice when a FAB is
      // visible, not from the theme.
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        width: 560,
        insetPadding: EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.xs, AppSpacing.m, AppSpacing.m),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

/// Financial domain colors that don't come out of a standard Material
/// `ColorScheme`. Never the only visual cue: on every screen that
/// uses them, a sign (+/-) or an icon always accompanies the color
/// (see `docs/design.md`).
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({required this.income, required this.expense, required this.warning});

  final Color income;
  final Color expense;

  /// Savings goals "por detrás" (neither on track nor overdue): amber,
  /// distinct from [income]/[expense] and always next to the status
  /// icon and text.
  final Color warning;

  @override
  FinanceColors copyWith({Color? income, Color? expense, Color? warning}) {
    return FinanceColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warning: warning ?? this.warning,
    );
  }

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
