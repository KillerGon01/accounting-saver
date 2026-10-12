import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El único archivo de `lib/` que puede importar `package:web` (ver el
/// import condicional en `lib/presentation/payroll/payroll_file_picker.dart`):
/// todo lo demás, incluido el propio `payroll_file_picker.dart` y su stub,
/// debe compilar en Android y en el runner de `flutter test` sin tocarlo.
const _allowedFile = 'lib/presentation/payroll/payroll_file_picker_web.dart';

void main() {
  test('ningún archivo de lib/ fuera de la implementación web importa package:web', () {
    final libDir = Directory('lib');
    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceAll('\\', '/');
      if (relativePath == _allowedFile) continue;

      final content = entity.readAsStringSync();
      if (content.contains("package:web/")) {
        offenders.add(relativePath);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Estos archivos importan package:web fuera de $_allowedFile: $offenders',
    );
  });
}
