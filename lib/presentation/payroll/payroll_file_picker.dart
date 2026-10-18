// File picker for choosing a payroll PDF, available only on web (see
// `PayrollScreen`, which only shows if `kIsWeb`). `dart:io` exists on
// Android, iOS, desktop, and in the `flutter test` runner (the Dart
// VM), but not on web (neither compiling to JS nor to Wasm): that's
// why the condition uses the empty implementation
// (`pickPayrollPdfBytes` throws) on everything that isn't web, and
// only the real one (with `package:web`) on web. This way `flutter
// build apk` and `flutter test` compile without touching
// `package:web` at all, and this is the app's only file that decides
// which of the two implementations is used.
export 'payroll_file_picker_web.dart'
    if (dart.library.io) 'payroll_file_picker_stub.dart';
