// Selector de archivo para elegir un PDF de nómina, solo disponible en
// web (ver `PayrollScreen`, que solo se muestra si `kIsWeb`). `dart:io`
// existe en Android, iOS, escritorio y en el runner de `flutter test`
// (la VM de Dart), pero no en web (ni compilando a JS ni a Wasm): por eso
// la condición usa la implementación vacía (`pickPayrollPdfBytes` lanza)
// en todo lo que no es web, y solo la real (con `package:web`) en web.
// Así `flutter build apk` y `flutter test` compilan sin tocar
// `package:web` para nada, y este es el único archivo de la app donde se
// decide cuál de las dos implementaciones se usa.
export 'payroll_file_picker_web.dart'
    if (dart.library.io) 'payroll_file_picker_stub.dart';
