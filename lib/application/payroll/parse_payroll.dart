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

/// Resultado de leer una nómina: la extracción tal cual, la validación en
/// código, los avisos a mostrar y, solo si la validación cuadra, una
/// propuesta de movimiento (todavía sin guardar: ver `ParsePayroll`).
class ParsePayrollResult {
  const ParsePayrollResult({
    required this.extraction,
    required this.validation,
    required this.warnings,
    this.proposedTransaction,
  });

  final ExtractedPayroll extraction;
  final PayrollValidation validation;

  /// En español, listos para mostrar tal cual: discrepancia del líquido,
  /// anomalías que ha observado el modelo, texto con instrucciones
  /// detectado en el documento, y conceptos de deducción sin descripción
  /// en el glosario.
  final List<String> warnings;

  /// `null` si [validation] no cuadra: nunca se propone un ingreso con
  /// cifras que no suman.
  final ParsedTransaction? proposedTransaction;
}

/// Lee un PDF de nómina con IA y lo convierte en un resultado validado en
/// código (nunca se fía de ningún cálculo del modelo).
///
/// Como [SendChatMessage] (`lib/application/chat/send_chat_message.dart`),
/// lleva su propio estado por instancia (el contador de lecturas de la
/// sesión): cada usuario obtiene su propia instancia a través de un
/// `Provider.family` por `userId` (ver `payrollProvider` en
/// `lib/presentation/payroll/payroll_providers.dart`), así que el contador
/// no se comparte entre dos usuarios ni se pierde al cerrar y reabrir la
/// pantalla para el mismo usuario.
class ParsePayroll {
  ParsePayroll(this._gateway);

  /// Tamaño máximo admitido para el PDF, en bytes.
  static const maxPdfBytes = 3 * 1024 * 1024;

  /// Tope de lecturas por sesión (una instancia de esta clase). Solo cuenta
  /// una lectura cuya validación en código cuadra de verdad (ver
  /// [PayrollValidation.matches]): ni un error del modelo, ni un timeout,
  /// ni una lectura que no cuadra gastan una de las 5, porque ninguna de
  /// las tres termina proponiendo un movimiento.
  static const maxReadsPerSession = 5;

  final PayrollGateway _gateway;
  int _readsUsed = 0;

  /// Lecturas que quedan en esta sesión antes de llegar a
  /// [maxReadsPerSession]. Nunca negativo.
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

    // Solo se cuenta aquí, y solo si la validación cuadra: una lectura que
    // no cuadra ha gastado cuota de Gemini igual que una que cuadra, pero
    // no gasta una de las 5 porque no termina proponiendo ningún
    // movimiento (ver el docstring de `maxReadsPerSession`).
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

    // Si el modelo ya ha descrito este mismo texto en `anomalies` (además
    // de registrarlo en `instruccionesEnDocumento`), no se duplica como un
    // segundo aviso: un único aviso por hecho, no dos sobre lo mismo.
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
