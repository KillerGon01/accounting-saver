/// Una deducción de la nómina, tal y como figura en el documento: el
/// concepto y el importe son una copia literal, nunca un cálculo (ver
/// [ExtractedPayroll]).
class PayrollDeduction {
  const PayrollDeduction({required this.concept, required this.cents});

  final String concept;
  final int cents;
}

/// Lo que el modelo ha extraído de un PDF de nómina, sin ninguna
/// validación todavía (ver `PayrollValidation` en
/// `lib/domain/payroll/payroll_validation.dart`, que sí valida, en código,
/// a partir de estos mismos campos). Todos los importes y textos deben ser
/// una copia literal del documento: ni la infraestructura que rellena esta
/// clase ni nadie más debe corregir ni recalcular nada aquí, ni siquiera
/// cuando el líquido no cuadre con bruto menos deducciones.
class ExtractedPayroll {
  const ExtractedPayroll({
    required this.periodStart,
    required this.periodEnd,
    required this.grossCents,
    required this.deductions,
    required this.netAsStatedCents,
    this.irpfPercent,
    required this.anomalies,
    this.documentInstructions,
  });

  /// Inicio del periodo que cubre la nómina, copiado del documento.
  final DateTime periodStart;

  /// Fin del periodo que cubre la nómina, copiado del documento. Es la
  /// fecha que se propone para el movimiento (ver `ParsePayroll`).
  final DateTime periodEnd;

  /// Importe bruto, en céntimos, copiado literal del documento.
  final int grossCents;

  final List<PayrollDeduction> deductions;

  /// Importe líquido (neto) tal y como figura en el documento, copiado
  /// literal aunque no cuadre con bruto menos deducciones: de eso se
  /// encarga `PayrollValidation`, no esta clase ni quien la rellena.
  final int netAsStatedCents;

  /// Porcentaje de IRPF copiado del documento, si lo indica. `null` si el
  /// documento no lo menciona.
  final double? irpfPercent;

  /// Cosas que el propio modelo ha observado como raras o que no cuadran,
  /// en texto. Puramente informativo: `PayrollValidation` no depende de
  /// esta lista para decidir si cuadra o no.
  final List<String> anomalies;

  /// Si el documento contiene algo que parezca una instrucción dirigida al
  /// modelo de IA (en vez de un dato de la nómina), su texto literal.
  /// `null` si no se ha detectado ninguna. Señal auxiliar, no fiable del
  /// todo (ver docs/security.md): no cambia ninguna cifra ni el
  /// comportamiento de la app, solo se muestra como aviso.
  final String? documentInstructions;
}
