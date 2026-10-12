import '../transactions/amount_limits.dart';
import 'extracted_payroll.dart';

/// Años entre los que se considera razonable el periodo de una nómina (ni
/// una fecha claramente mal reconocida del documento, como el año 1 o el
/// año 9999, ni una del futuro lejano). No es una validación de negocio
/// real (no existe tal cosa para una nómina), solo un filtro de cordura
/// sobre lo que ha copiado el modelo.
const minReasonablePayrollYear = 2000;
const maxReasonablePayrollYear = 2100;

/// Cuántos días, como mucho, puede durar el periodo de una nómina. Una
/// nómina cubre normalmente un mes; se deja margen (una nómina podría
/// cubrir, por ejemplo, un trimestre) sin llegar a aceptar un periodo que
/// claramente no es el de una sola nómina.
const maxReasonablePayrollPeriodDays = 95;

/// El porcentaje de una deducción sobre el bruto, calculado en código (no
/// por el modelo): `cents / grossCents * 100`.
class PayrollDeductionBreakdown {
  const PayrollDeductionBreakdown({
    required this.concept,
    required this.cents,
    required this.percentOfGross,
  });

  final String concept;
  final int cents;
  final double percentOfGross;
}

/// Validación en código de una [ExtractedPayroll], calculada a partir de
/// sus cifras tal y como las ha copiado el modelo. Nunca se fía de ningún
/// cálculo que el modelo diga haber hecho (ni de `anomalies`, que es solo
/// informativo): todo lo de aquí se recalcula desde cero a partir de
/// [ExtractedPayroll.grossCents], [ExtractedPayroll.deductions] y
/// [ExtractedPayroll.netAsStatedCents].
class PayrollValidation {
  const PayrollValidation({
    required this.deductionsTotalCents,
    required this.discrepancyCents,
    required this.deductionBreakdown,
    required this.amountsAreValid,
    required this.datesAreCoherent,
  });

  factory PayrollValidation.fromExtraction(ExtractedPayroll extraction) {
    final total = extraction.deductions.fold(0, (sum, deduction) => sum + deduction.cents);
    final discrepancy = extraction.grossCents - total - extraction.netAsStatedCents;

    final breakdown = [
      for (final deduction in extraction.deductions)
        PayrollDeductionBreakdown(
          concept: deduction.concept,
          cents: deduction.cents,
          percentOfGross: extraction.grossCents > 0
              ? deduction.cents / extraction.grossCents * 100
              : 0,
        ),
    ];

    final amountsAreValid = _isPositiveAndWithinLimit(extraction.grossCents) &&
        _isPositiveAndWithinLimit(extraction.netAsStatedCents) &&
        extraction.deductions.every((d) => _isPositiveAndWithinLimit(d.cents));

    final periodDays = extraction.periodEnd.difference(extraction.periodStart).inDays;
    final datesAreCoherent = !extraction.periodEnd.isBefore(extraction.periodStart) &&
        periodDays <= maxReasonablePayrollPeriodDays &&
        extraction.periodStart.year >= minReasonablePayrollYear &&
        extraction.periodEnd.year <= maxReasonablePayrollYear;

    return PayrollValidation(
      deductionsTotalCents: total,
      discrepancyCents: discrepancy,
      deductionBreakdown: breakdown,
      amountsAreValid: amountsAreValid,
      datesAreCoherent: datesAreCoherent,
    );
  }

  /// Suma de todas las deducciones, en céntimos.
  final int deductionsTotalCents;

  /// `grossCents - deductionsTotalCents - netAsStatedCents`. Cero si el
  /// líquido declarado cuadra exactamente con bruto menos deducciones.
  final int discrepancyCents;

  final List<PayrollDeductionBreakdown> deductionBreakdown;

  /// `false` si el bruto, el líquido o alguna deducción es cero, negativo,
  /// o supera `maxAbsoluteAmountCents` (la misma constante del dominio que
  /// limita cualquier movimiento, ver `amount_limits.dart`).
  final bool amountsAreValid;

  /// `false` si el fin del periodo es anterior a su inicio, el periodo
  /// dura más de [maxReasonablePayrollPeriodDays], o alguna de las dos
  /// fechas cae fuera de [minReasonablePayrollYear]..[maxReasonablePayrollYear].
  final bool datesAreCoherent;

  /// `true` solo si el líquido declarado cuadra exactamente con bruto
  /// menos deducciones, los importes son válidos y las fechas son
  /// coherentes. Es la única condición que decide si se propone un
  /// ingreso (ver `ParsePayroll`).
  bool get matches => discrepancyCents == 0 && amountsAreValid && datesAreCoherent;

  static bool _isPositiveAndWithinLimit(int cents) => cents > 0 && cents <= maxAbsoluteAmountCents;
}
