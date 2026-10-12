import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Abre el selector de archivos del navegador filtrado a PDF y devuelve
/// los bytes del primero que se elija, o `null` si no se elige ninguno.
/// Nunca escribe el archivo en ningún sitio: solo vive en memoria mientras
/// dura esta llamada y lo que haga quien la invoque con el resultado.
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
