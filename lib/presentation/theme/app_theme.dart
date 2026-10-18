import 'package:flutter/material.dart';

const _seedColor = Color(0xFF00695C);

abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// `AppTheme.dark()` es el único tema que usa la app (`MaterialApp` en
/// `main.dart` fuerza `themeMode: ThemeMode.dark`): fondo casi negro con un
/// tono verdoso muy sutil, superficies en capas, acento teal/menta e
/// ingresos/gastos en verde/coral suaves (ver `FinanceColors`), siempre
/// acompañados de signo o icono, nunca solo de color. `AppTheme.light()` se
/// conserva (código muerto a propósito, por si se retoma el modo claro más
/// adelante) pero ningún `MaterialApp` de la app lo usa; sí lo siguen usando
/// los tests que montan su propio `MaterialApp` con `theme:` explícito.
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

  /// Paleta oscura a mano, no la generada por defecto de `ColorScheme.fromSeed`:
  /// se parte del esquema derivado de la semilla (para que `primary`,
  /// `secondary`, etc. sigan siendo coherentes entre sí) y se sobrescriben
  /// con `copyWith` las superficies (fondo casi negro con un tono verdoso
  /// apenas perceptible, en capas cada vez más claras) y los acentos
  /// (teal/menta, coral suave en vez del rojo de Material por defecto).
  /// Contraste comprobado a mano (fórmula WCAG de luminancia relativa):
  /// `onSurface` da más de 16:1 sobre `surface`. `onSurfaceVariant` (las
  /// etiquetas secundarias: "Balance del mes", fechas, "N movimientos"...)
  /// se subió de `#A9BDB4` a `#BFD0C8` para ganar margen sobre el mínimo
  /// AA de texto normal (4,5:1): da ahora casi 12:1 sobre `surface`, casi
  /// 10:1 sobre `surfaceContainerHigh` y más de 9:1 sobre la superficie más
  /// clara del tema (`surfaceContainerHighest`) — el peor de los tres
  /// casos sigue más que duplicando el mínimo. Igual de holgado para
  /// `income`, `expense`/`error` y `warning`.
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
    // Coral suave: también `FinanceColors.expense` (ver más abajo), para
    // que el gasto y "error" sean el mismo tono, nunca dos rojos distintos.
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
        // Etiquetas pequeñas (p. ej. "Balance del mes" y las cabeceras de
        // cada tarjeta del resumen mensual) en gris tenue, para que
        // destaquen la cifra y el contenido, no el rótulo que los precede.
        labelLarge: base.textTheme.labelLarge?.copyWith(color: onSurfaceVariant),
        // Etiquetas secundarias (fechas, "N movimientos", pies de tarjeta...):
        // mismo gris tenue que `labelLarge` y, por defecto, 12 px en vez de
        // los 11 px por defecto de Material 3 — tamaño mínimo legible para
        // texto que ya de por sí tiene menos contraste que el contenido
        // principal. Algunas pantallas ya fijaban este mismo color a mano
        // con `.copyWith(color: onSurfaceVariant)`; seguir haciéndolo no
        // cambia nada (mismo color), así que no hizo falta tocarlas.
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
      // `width` fija un ancho máximo (y lo centra: ver `_ScaffoldLayout` en
      // el SDK de Flutter, que calcula el offset horizontal solo cuando hay
      // un ancho explícito) en vez de ocupar todo el ancho menos el margen,
      // para que no cambie de tamaño entre pantallas con un `ConstrainedBox`
      // más estrecho que otras. `insetPadding` fijo por el mismo motivo de
      // estabilidad, aunque esto no evita el "salto" vertical que causa el
      // `FloatingActionButton` (ver docs/design.md, "Aviso estable al
      // navegar"): ese salto viene de dónde posiciona el `Scaffold` el
      // aviso cuando hay un FAB visible, no del tema.
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

/// Colores de dominio financiero que no salen de un `ColorScheme` estándar
/// de Material. Nunca es la única pista visual: en todas las pantallas que
/// los usan, el signo (+/-) o un icono acompañan siempre al color (ver
/// `docs/design.md`).
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({required this.income, required this.expense, required this.warning});

  final Color income;
  final Color expense;

  /// Metas de ahorro "por detrás" (ni al día ni vencidas): ámbar, distinto
  /// de [income]/[expense] y siempre junto al icono y el texto del estado.
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
