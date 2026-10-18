import 'package:accounting_saver/application/chat/send_chat_message.dart';
import 'package:accounting_saver/application/payroll/parse_payroll.dart';
import 'package:accounting_saver/application/reports/explain_monthly_report.dart';
import 'package:accounting_saver/application/savings/create_savings_goal.dart';
import 'package:accounting_saver/application/savings/explain_savings_suggestions.dart';
import 'package:accounting_saver/presentation/help/help_content.dart';
import 'package:accounting_saver/presentation/help/help_topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada pantalla tiene una entrada de ayuda con título y pasos', () {
    for (final topic in HelpTopic.values) {
      final entry = helpContent[topic];
      expect(entry, isNotNull, reason: 'Falta contenido de ayuda para $topic');
      expect(entry!.title, isNotEmpty, reason: 'Título vacío para $topic');
      expect(entry.steps, isNotEmpty, reason: 'Sin pasos para $topic');
      for (final step in entry.steps) {
        expect(step, isNotEmpty, reason: 'Paso vacío en $topic');
      }
    }
  });

  test('el chat menciona el máximo real de preguntas por sesión', () {
    final entry = helpContent[HelpTopic.chat]!;
    expect(
      entry.steps.any((step) => step.contains('${SendChatMessage.maxQuestionsPerSession} preguntas')),
      isTrue,
    );
  });

  test('leer nómina menciona el máximo real de lecturas por sesión', () {
    final entry = helpContent[HelpTopic.payroll]!;
    expect(
      entry.steps.any((step) => step.contains('${ParsePayroll.maxReadsPerSession} lecturas')),
      isTrue,
    );
  });

  test('el resumen del mes menciona el máximo real de comentarios con IA por sesión', () {
    final entry = helpContent[HelpTopic.monthlyReport]!;
    expect(
      entry.steps.any((step) => step.contains('${ExplainMonthlyReport.maxCommentsPerSession} veces')),
      isTrue,
    );
  });

  test('las metas de ahorro mencionan el máximo real de metas por usuario', () {
    final entry = helpContent[HelpTopic.savingsGoals]!;
    expect(
      entry.steps.any((step) => step.contains('${CreateSavingsGoal.maxGoalsPerUser} metas')),
      isTrue,
    );
  });

  test('las metas de ahorro mencionan el máximo real de redacciones con IA por sesión', () {
    final entry = helpContent[HelpTopic.savingsGoals]!;
    expect(
      entry.steps.any((step) => step.contains('${ExplainSavingsSuggestions.maxExplanationsPerSession} veces')),
      isTrue,
    );
  });
}
