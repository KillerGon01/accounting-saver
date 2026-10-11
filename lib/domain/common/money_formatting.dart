/// Céntimos de euro, ya en valor absoluto (sin signo), a texto con coma
/// decimal y dos decimales (por ejemplo, 1299 → "12,99"). Sin separador de
/// miles ni símbolo de moneda: para eso está `formatCents` en
/// `presentation/transactions/formatters.dart`, que es la única capa con
/// permiso para decidir cómo se ve un importe en pantalla. Esta función
/// pura (sin Firebase ni Flutter) es la que usan el dominio y la
/// aplicación (por ejemplo, las funciones del chat) cuando necesitan un
/// importe en euros sin depender de la capa de presentación.
String formatEuroAmount(int amountCentsAbs) {
  final euros = amountCentsAbs ~/ 100;
  final decimals = (amountCentsAbs % 100).toString().padLeft(2, '0');
  return '$euros,$decimals';
}
