/// Resultado sin validar que devuelve [LlmGateway]. La categoría llega como
/// texto porque la IA puede devolver un valor que no exista en [Category];
/// el caso de uso es quien la valida y la convierte en [ParsedTransaction].
///
/// Si el texto no describía con claridad un movimiento con importe,
/// [understood] es `false` y el resto de campos son `null`: la IA no debe
/// inventar un importe, un concepto ni una categoría que no estén en el
/// texto.
class RawParsedTransaction {
  const RawParsedTransaction({
    required this.understood,
    this.amountCents,
    this.date,
    this.description,
    this.categoryName,
  });

  final bool understood;

  /// Negativo = gasto. `null` si [understood] es `false`.
  final int? amountCents;
  final DateTime? date;
  final String? description;

  /// Nombre de un valor de `Category`. Puede no existir en el enum.
  final String? categoryName;
}
