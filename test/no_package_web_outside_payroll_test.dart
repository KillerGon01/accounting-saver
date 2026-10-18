import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only file in `lib/` that may import `package:web` (see the
/// conditional import in `lib/presentation/payroll/payroll_file_picker.dart`):
/// everything else, including `payroll_file_picker.dart` itself and its
/// stub, must compile on Android and in the `flutter test` runner without touching it.
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
