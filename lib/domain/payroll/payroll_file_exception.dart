/// The chosen file isn't a valid PDF or exceeds the maximum size (see
/// `ParsePayroll.maxPdfBytes`), checked in code before calling the
/// model: it doesn't spend Gemini quota or count as a reading of the
/// session.
class PayrollFileException implements Exception {
  const PayrollFileException(this.message);

  final String message;

  @override
  String toString() => 'PayrollFileException: $message';
}
