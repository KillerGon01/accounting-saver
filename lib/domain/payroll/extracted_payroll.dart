/// A payroll deduction, exactly as it appears on the document: the
/// concept and the amount are a literal copy, never a calculation (see
/// [ExtractedPayroll]).
class PayrollDeduction {
  const PayrollDeduction({required this.concept, required this.cents});

  final String concept;
  final int cents;
}

/// What the model extracted from a payroll PDF, with no validation yet
/// (see `PayrollValidation` in `lib/domain/payroll/payroll_validation.dart`,
/// which does validate, in code, from these same fields). All amounts
/// and text must be a literal copy of the document: neither the
/// infrastructure layer that fills this class nor anyone else should
/// correct or recompute anything here, not even when the net pay
/// doesn't match gross pay minus deductions.
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

  /// Start of the period the payroll covers, copied from the document.
  final DateTime periodStart;

  /// End of the period the payroll covers, copied from the document.
  /// It's the date proposed for the transaction (see `ParsePayroll`).
  final DateTime periodEnd;

  /// Gross amount, in cents, copied literally from the document.
  final int grossCents;

  final List<PayrollDeduction> deductions;

  /// Net pay amount exactly as it appears on the document, copied
  /// literally even if it doesn't match gross pay minus deductions:
  /// that's `PayrollValidation`'s job, not this class's or its filler's.
  final int netAsStatedCents;

  /// IRPF percentage copied from the document, if it states one. `null`
  /// if the document doesn't mention it.
  final double? irpfPercent;

  /// Things the model itself has flagged as odd or not matching up, as
  /// text. Purely informative: `PayrollValidation` doesn't rely on this
  /// list to decide whether things match.
  final List<String> anomalies;

  /// If the document contains something that looks like an instruction
  /// aimed at the AI model (rather than payroll data), its literal
  /// text. `null` if none was detected. An auxiliary signal, not fully
  /// reliable (see docs/security.md): it doesn't change any figure or
  /// the app's behavior, it's only shown as a notice.
  final String? documentInstructions;
}
