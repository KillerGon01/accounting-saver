/// El texto en lenguaje natural no describe un movimiento con un importe
/// claro: ni la IA ha podido extraerlo, ni el propio texto menciona ningún
/// número. No se abre el formulario con una propuesta inventada.
class NotUnderstoodException implements Exception {
  const NotUnderstoodException([
    this.message = 'No he encontrado un importe en el texto. Prueba con algo '
        'como «12,50 en el bar ayer»',
  ]);

  final String message;

  @override
  String toString() => 'NotUnderstoodException: $message';
}
