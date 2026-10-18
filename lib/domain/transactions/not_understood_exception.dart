/// The natural language text doesn't describe a transaction with a
/// clear amount: neither has the AI been able to extract one, nor does
/// the text itself mention any number. The form isn't opened with a
/// made-up draft.
class NotUnderstoodException implements Exception {
  const NotUnderstoodException([
    this.message = 'No he encontrado un importe en el texto. Prueba con algo '
        'como «12,50 en el bar ayer»',
  ]);

  final String message;

  @override
  String toString() => 'NotUnderstoodException: $message';
}
