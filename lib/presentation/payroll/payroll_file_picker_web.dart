import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens the browser's file picker filtered to PDF and returns the
/// bytes of the first one chosen, or `null` if none is chosen. Never
/// writes the file anywhere: it only lives in memory for the
/// duration of this call and whatever the caller does with the
/// result.
Future<Uint8List?> pickPayrollPdfBytes() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'application/pdf';
  final completer = Completer<Uint8List?>();
  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      final file = (files != null && files.length > 0) ? files.item(0) : null;
      if (file == null) {
        completer.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then((buffer) {
        completer.complete(buffer.toDart.asUint8List());
      });
    }.toJS,
  );
  input.click();
  return completer.future;
}
