import 'dart:typed_data';

import '../../domain/payroll/extracted_payroll.dart';
import '../../domain/payroll/payroll_file_exception.dart';
import '../../domain/payroll/payroll_gateway.dart';
import '../../domain/payroll/payroll_glossary.dart';
import '../../domain/payroll/payroll_validation.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../../domain/transactions/parsed_transaction.dart';

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Result of reading a payroll: the extraction as is, the code-side
/// validation, the warnings to show and, only if the validation
/// matches, a transaction draft (not saved yet: see `ParsePayroll`).
class ParsePayrollResult {
  const ParsePayrollResult({
    required this.extraction,
    required this.validation,
    required this.warnings,
    this.proposedTransaction,
  });

  final ExtractedPayroll extraction;
  final PayrollValidation validation;

  /// In Spanish, ready to show as-is: net pay discrepancy, anomalies
  /// the model has observed, instruction-like text detected in the
  /// document, and deduction concepts with no description in the
  /// glossary.
  final List<String> warnings;

  /// `null` if [validation] doesn't match: an income is never
  /// proposed with figures that don't add up.
  final ParsedTransaction? proposedTransaction;
}

/// Reads a payroll PDF with AI and turns it into a code-validated
/// result (never trusts any calculation from the model).
///
/// Like [SendChatMessage] (`lib/application/chat/send_chat_message.dart`),
/// it carries its own per-instance state (the session's reading
/// counter): each user gets their own instance through a
/// `Provider.family` by `userId` (see `payrollProvider` in
/// `lib/presentation/payroll/payroll_providers.dart`), so the counter
/// isn't shared between two users nor lost when closing and reopening
/// the screen for the same user.
class ParsePayroll {
  ParsePayroll(this._gateway);

  /// Maximum size allowed for the PDF, in bytes.
  static const maxPdfBytes = 3 * 1024 * 1024;

  /// Cap on readings per session (one instance of this class). Only a
  /// reading whose code-side validation truly matches counts (see
  /// [PayrollValidation.matches]): neither a model error, nor a
  /// timeout, nor a reading that doesn't match spend one of the 5,
  /// because none of the three ends up proposing a transaction.
  static const maxReadsPerSession = 5;

  final PayrollGateway _gateway;
  int _readsUsed = 0;

  /// Readings left in this session before reaching
  /// [maxReadsPerSession]. Never negative.
  int get remainingReads => (maxReadsPerSession - _readsUsed).clamp(0, maxReadsPerSession);

  Future<ParsePayrollResult> call(Uint8List pdfBytes) async {
    if (_readsUsed >= maxReadsPerSession) {
      throw const LlmGatewayException(
        'session-limit-reached',
        message: 'Has llegado al máximo de lecturas de esta sesión.',
      );
    }
    if (pdfBytes.length > maxPdfBytes) {
      throw const PayrollFileException('El archivo supera el tamaño máximo de 3 MB.');
    }
    if (!_looksLikePdf(pdfBytes)) {
      throw const PayrollFileException('El archivo no es un PDF.');
    }

    final extraction = await _gateway.extractPayroll(pdfBytes);
    final validation = PayrollValidation.fromExtraction(extraction);

    // Only counted here, and only if the validation matches: a
    // reading that doesn't match has spent Gemini quota just like one
    // that matches, but it doesn't spend one of the 5 because it
    // doesn't end up proposing any transaction (see
    // `maxReadsPerSession`'s docstring).
    if (validation.matches) _readsUsed++;

    return ParsePayrollResult(
      extraction: extraction,
      validation: validation,
      warnings: _buildWarnings(extraction, validation),
      proposedTransaction: validation.matches ? _buildProposal(extraction) : null,
    );
  }

  bool _looksLikePdf(Uint8List bytes) {
    const signature = [0x25, 0x50, 0x44, 0x46]; // "%PDF"
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  List<String> _buildWarnings(ExtractedPayroll extraction, PayrollValidation validation) {
    final warnings = <String>[];

    if (validation.discrepancyCents != 0) {
      warnings.add(
        'El líquido del documento no cuadra con bruto menos deducciones: '
        'discrepancia de ${_centsLabel(validation.discrepancyCents.abs())}.',
      );
    }
    if (!validation.amountsAreValid) {
      warnings.add('Alguno de los importes del documento no es válido.');
    }
    if (!validation.datesAreCoherent) {
      warnings.add('Las fechas del periodo no son coherentes.');
    }
    final documentInstructions = extraction.documentInstructions;
    final normalizedInstructions = documentInstructions?.trim().toLowerCase();

    // If the model has already described this same text in
    // `anomalies` (besides recording it in `instruccionesEnDocumento`),
    // it isn't duplicated as a second warning: a single warning per
    // fact, not two about the same thing.
    for (final anomaly in extraction.anomalies) {
      final normalizedAnomaly = anomaly.trim().toLowerCase();
      final describesSameInstructions = normalizedInstructions != null &&
          (normalizedAnomaly.contains(normalizedInstructions) ||
              normalizedInstructions.contains(normalizedAnomaly));
      if (describesSameInstructions) continue;
      warnings.add(anomaly);
    }
    if (documentInstructions != null) {
      warnings.add(
        'El documento contiene texto que parece una instrucción dirigida a '
        'la IA; se ha registrado como dato, no se ha obedecido: '
        '"$documentInstructions"',
      );
    }
    for (final deduction in extraction.deductions) {
      if (payrollGlossaryDescription(deduction.concept) == payrollGlossaryUnknownDescription) {
        warnings.add('El concepto "${deduction.concept}" no tiene descripción en el glosario.');
      }
    }

    return warnings;
  }

  ParsedTransaction _buildProposal(ExtractedPayroll extraction) {
    return ParsedTransaction(
      amountCents: extraction.netAsStatedCents,
      date: extraction.periodEnd,
      description: 'Nómina ${_monthYear(extraction.periodEnd)}',
      categoryId: Category.nomina,
    );
  }

  String _monthYear(DateTime date) {
    final name = _monthNames[date.month - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${date.year}';
  }

  String _centsLabel(int cents) {
    final euros = cents ~/ 100;
    final decimals = (cents % 100).toString().padLeft(2, '0');
    return '$euros,$decimals €';
  }
}
