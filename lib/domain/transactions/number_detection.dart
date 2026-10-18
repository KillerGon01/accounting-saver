const _spanishNumberWords = [
  'cero', 'un', 'uno', 'una', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete',
  'ocho', 'nueve', 'diez', 'once', 'doce', 'trece', 'catorce', 'quince',
  'dieciseis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte',
  'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa',
  'cien', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos',
  'seiscientos', 'setecientos', 'ochocientos', 'novecientos',
  'mil', 'millon', 'millones',
];

/// Indicates whether [text] mentions any digit or any Spanish number
/// word ("doce", "veinte", "cien", "mil"...). Serves as a deterministic
/// check before accepting an amount: if the text doesn't mention any
/// number, it can't possibly describe a transaction with an amount, no
/// matter what the AI claims.
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
