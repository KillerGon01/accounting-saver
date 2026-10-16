// Genera el icono de la app (una moneda con una flecha ascendente) en
// todos los tamaños que necesitan web y Android, a partir de un único
// conjunto de coordenadas vectoriales definidas aquí mismo (ver
// docs/design.md, "Identidad visual"). También escribe
// `assets/branding/icon.svg`: el mismo dibujo en SVG, para tener una
// fuente vectorial legible en el repo — generada por este script, nunca
// a mano, para que nunca se desincronice de los PNG.
//
// No es un test: no hace ninguna aserción, solo escribe archivos. Vive
// fuera de `test/` a propósito para que `flutter test` (sin argumentos)
// nunca lo recoja ni lo cuente. Se ejecuta a mano:
//
//   flutter test tool/generate_icons.dart
//
// Usa `flutter test` solo porque es el único punto de entrada de este
// proyecto con el motor de Flutter ya inicializado para poder rasterizar
// con `dart:ui` (ningún rasterizador de SVG estaba instalado al escribir
// esto); `lib/eval_main.dart` usa `flutter run` por un motivo
// equivalente (ver "Por qué no puede ser un script de Dart puro ni
// correr en CI" en docs/evaluation.md).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Fondo oscuro casi negro con tono verdoso: el mismo `surface` de
/// `AppTheme.dark()` (`lib/presentation/theme/app_theme.dart`).
const _backgroundColor = 0xFF0B120F;

/// Teal/menta: el mismo `primary` de `AppTheme.dark()`.
const _symbolColor = 0xFF4DB6AC;

/// Icono monocromo (Android 13+): una sola forma con alfa, sin color
/// propio — el sistema la tiñe con el color que elija. El valor exacto
/// no importa, solo que tenga alfa 255 donde se vea el símbolo; se usa
/// negro por convención.
const _monochromeColor = 0xFF000000;

/// Todo el dibujo vive en un lienzo cuadrado de 100x100 unidades,
/// pensado para caber dentro de la zona segura circular más estricta de
/// las dos que exige este icono: el círculo de 66dp sobre un lienzo de
/// 108dp de un icono adaptativo de Android (radio ≈30,5 % del lienzo,
/// medido desde el centro). El punto más alejado del centro aquí es la
/// base de la moneda, a 23 unidades — con margen de sobra bajo ese
/// 30,5 %. Esa misma geometría, al caber en la zona circular más
/// estricta, cabe también dentro de la zona segura "80 % central"
/// (cuadrada, más laxa) que piden los maskable de web: una sola
/// geometría sirve para las dos sin necesidad de dos variantes.
void _paintSymbol(Canvas canvas, double size, int color) {
  final scale = size / 100;
  final paint = Paint()..color = Color(color);

  // Moneda.
  canvas.drawCircle(Offset(50 * scale, 60 * scale), 13 * scale, paint);

  // Vástago de la flecha, uniendo la moneda con la punta.
  canvas.drawRect(Rect.fromLTWH(46 * scale, 46 * scale, 8 * scale, 14 * scale), paint);

  // Punta de la flecha.
  final arrowHead = Path()
    ..moveTo(38 * scale, 46 * scale)
    ..lineTo(62 * scale, 46 * scale)
    ..lineTo(50 * scale, 28 * scale)
    ..close();
  canvas.drawPath(arrowHead, paint);
}

Future<Uint8List> _renderPng({
  required double size,
  required bool withBackground,
  int symbolColor = _symbolColor,
}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  if (withBackground) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(_backgroundColor));
  }
  _paintSymbol(canvas, size, symbolColor);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.round(), size.round());
  final bytes = await image.toByteData(format: ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

Future<void> _writePng(
  String path, {
  required double size,
  required bool withBackground,
  int symbolColor = _symbolColor,
}) async {
  final bytes = await _renderPng(size: size, withBackground: withBackground, symbolColor: symbolColor);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  // ignore: avoid_print
  print('Escrito: $path (${size.round()}x${size.round()})');
}

String _buildSvg() {
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- Generado por tool/generate_icons.dart — no editar a mano, ver docs/design.md "Identidad visual". -->
  <rect width="100" height="100" fill="#0B120F"/>
  <g fill="#4DB6AC">
    <circle cx="50" cy="60" r="13"/>
    <rect x="46" y="46" width="8" height="14"/>
    <polygon points="38,46 62,46 50,28"/>
  </g>
</svg>
''';
}

void main() {
  testWidgets('generar los iconos de la app (herramienta, no un test de comportamiento)', (tester) async {
    // `toImage`/`toByteData` son async de verdad (decodifican con el
    // motor, no con el reloj falso de `flutter test`): sin `runAsync`
    // nunca resuelven dentro de una `testWidgets` normal.
    await tester.runAsync(() async {
      final svgFile = File('assets/branding/icon.svg');
      await svgFile.parent.create(recursive: true);
      await svgFile.writeAsString(_buildSvg());
      // ignore: avoid_print
      print('Escrito: ${svgFile.path}');

      // Web: iconos "any" (con fondo a sangre completa) y maskable
      // (mismo fondo a sangre completa; el símbolo ya cabe en la zona
      // segura — ver el comentario de `_paintSymbol`).
      await _writePng('web/favicon.png', size: 16, withBackground: true);
      await _writePng('web/icons/Icon-192.png', size: 192, withBackground: true);
      await _writePng('web/icons/Icon-512.png', size: 512, withBackground: true);
      await _writePng('web/icons/Icon-maskable-192.png', size: 192, withBackground: true);
      await _writePng('web/icons/Icon-maskable-512.png', size: 512, withBackground: true);

      // Android: icono heredado (pre-Android 8, con fondo) en las 5
      // densidades estándar.
      const legacySizes = {
        'mdpi': 48.0,
        'hdpi': 72.0,
        'xhdpi': 96.0,
        'xxhdpi': 144.0,
        'xxxhdpi': 192.0,
      };
      for (final entry in legacySizes.entries) {
        await _writePng(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
          size: entry.value,
          withBackground: true,
        );
      }

      // Android: icono adaptativo (foreground, sin fondo — el fondo es
      // el color de recurso `ic_launcher_background`, ver
      // `android/app/src/main/res/values/colors.xml`) y su versión
      // monocroma (Android 13+), en un lienzo de 108dp por densidad.
      const adaptiveSizes = {
        'mdpi': 108.0,
        'hdpi': 162.0,
        'xhdpi': 216.0,
        'xxhdpi': 324.0,
        'xxxhdpi': 432.0,
      };
      for (final entry in adaptiveSizes.entries) {
        await _writePng(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
          size: entry.value,
          withBackground: false,
        );
        await _writePng(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_monochrome.png',
          size: entry.value,
          withBackground: false,
          symbolColor: _monochromeColor,
        );
      }
    });
  });
}
