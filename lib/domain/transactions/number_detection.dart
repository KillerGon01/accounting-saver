const _spanishNumberWords = [
  'cero', 'un', 'uno', 'una', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete',
  'ocho', 'nueve', 'diez', 'once', 'doce', 'trece', 'catorce', 'quince',
  'dieciseis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte',
  'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa',
  'cien', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos',
  'seiscientos', 'setecientos', 'ochocientos', 'novecientos',
  'mil', 'millon', 'millones',
];

/// Indica si [text] menciona alguna cifra o alguna palabra de número en
/// español ("doce", "veinte", "cien", "mil"...). Sirve de contraste
/// determinista antes de aceptar un importe: si el texto no menciona
/// ningún número, de ninguna forma puede describir un movimiento con
/// importe, por mucho que la IA diga lo contrario.
bool textContainsNumber(String text) {
  if (RegExp(r'\d').hasMatch(text)) return true;

  final normalized = _stripAccents(text.toLowerCase());
  return _spanishNumberWords.any(
    (word) => RegExp('\\b$word\\b').hasMatch(normalized),
  );
}

String _stripAccents(String input) {
  const accented = 'áéíóúü';
  const plain = 'aeiouu';
  var result = input;
  for (var i = 0; i < accented.length; i++) {
    result = result.replaceAll(accented[i], plain[i]);
  }
  return result;
}
