import '../transactions/amount_limits.dart';
import 'extracted_payroll.dart';

/// Years between which a payroll's period is considered reasonable
/// (neither a clearly misread date from the document, like the year 1
/// or the year 9999, nor one in the far future). Not a real business
/// validation (there's no such thing for a payroll), just a sanity
/// filter over what the model copied.
const minReasonablePayrollYear = 2000;
const maxReasonablePayrollYear = 2100;

/// How many days, at most, a payroll's period can last. A payroll
/// normally covers a month; some margin is left (a payroll could cover,
/// say, a quarter) without going so far as to accept a period that
/// clearly isn't a single payroll's.
const maxReasonablePayrollPeriodDays = 95;

/// A deduction's percentage of the gross amount, computed in code (not
/// by the model): `cents / grossCents * 100`.
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

/// Code-side validation of an [ExtractedPayroll], computed from its
/// figures exactly as the model copied them. Never trusts any
/// calculation the model claims to have done (nor `anomalies`, which is
/// only informative): everything here is recomputed from scratch from
/// [ExtractedPayroll.grossCents], [ExtractedPayroll.deductions] and
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

  /// Sum of all deductions, in cents.
  final int deductionsTotalCents;

  /// `grossCents - deductionsTotalCents - netAsStatedCents`. Zero if the
  /// stated net pay matches gross pay minus deductions exactly.
  final int discrepancyCents;

  final List<PayrollDeductionBreakdown> deductionBreakdown;

  /// `false` if the gross amount, the net amount, or any deduction is
  /// zero, negative, or exceeds `maxAbsoluteAmountCents` (the same
  /// domain constant that limits any transaction, see
  /// `amount_limits.dart`).
  final bool amountsAreValid;

  /// `false` if the period's end is before its start, the period lasts
  /// longer than [maxReasonablePayrollPeriodDays], or either date falls
  /// outside [minReasonablePayrollYear]..[maxReasonablePayrollYear].
  final bool datesAreCoherent;

  /// `true` only if the stated net pay matches gross pay minus
  /// deductions exactly, the amounts are valid, and the dates are
  /// coherent. The only condition that decides whether an income is
  /// proposed (see `ParsePayroll`).
  bool get matches => discrepancyCents == 0 && amountsAreValid && datesAreCoherent;

  static bool _isPositiveAndWithinLimit(int cents) => cents > 0 && cents <= maxAbsoluteAmountCents;
}
