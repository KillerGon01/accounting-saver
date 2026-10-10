import 'package:accounting_saver/application/reports/explain_monthly_report.dart';
import 'package:accounting_saver/domain/common/transactions_change_notifier.dart';
import 'package:accounting_saver/domain/reports/monthly_report.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_monthly_report_gateway.dart';

void main() {
  MonthlyReport reportOf(int year, int month) {
    return MonthlyReport(
      year: year,
      month: month,
      incomeCents: 100000,
      expenseCents: 50000,
      transactionCount: 5,
      categoryBreakdown: const [],
      comparison: null,
      truncated: false,
      isCurrentMonth: false,
      elapsedDays: null,
    );
  }

  test('devuelve el comentario del gateway', () async {
    final gateway = FakeMonthlyReportGateway.returning('Has gastado la mitad de lo que ingresaste.');
    final useCase = ExplainMonthlyReport(gateway);

    final comment = await useCase(report: reportOf(2026, 10));

    expect(comment, 'Has gastado la mitad de lo que ingresaste.');
    expect(gateway.lastReport?.year, 2026);
  });

  test('rechaza una segunda petición mientras la primera está en curso', () async {
    final gateway = FakeMonthlyReportGateway.returning('ok');
    final useCase = ExplainMonthlyReport(gateway);

    final first = useCase(report: reportOf(2026, 10));
    expect(() => useCase(report: reportOf(2026, 10)), throwsA(isA<StateError>()));
    await first;
  });

  group('tope de comentarios por sesión', () {
    test('permite hasta maxCommentsPerSession (3) con éxito', () async {
      final gateway = FakeMonthlyReportGateway.returning('ok');
      final useCase = ExplainMonthlyReport(gateway);

      await useCase(report: reportOf(2026, 10));
      await useCase(report: reportOf(2026, 9));
      await useCase(report: reportOf(2026, 8));

      expect(useCase.remainingComments, 0);
    });

    test('rechaza el cuarto comentario sin llamar al gateway', () async {
      final gateway = FakeMonthlyReportGateway.returning('ok');
      final useCase = ExplainMonthlyReport(gateway);

      await useCase(report: reportOf(2026, 10));
      await useCase(report: reportOf(2026, 9));
      await useCase(report: reportOf(2026, 8));
      final callsBeforeLimit = gateway.callCount;

      await expectLater(
        useCase(report: reportOf(2026, 7)),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'comment-limit-reached')),
      );
      expect(gateway.callCount, callsBeforeLimit);
    });

    test('una respuesta servida desde la caché no consume cupo', () async {
      final gateway = FakeMonthlyReportGateway.returning('ok');
      final useCase = ExplainMonthlyReport(gateway);

      await useCase(report: reportOf(2026, 10));
      expect(useCase.remainingComments, ExplainMonthlyReport.maxCommentsPerSession - 1);

      await useCase(report: reportOf(2026, 10));
      expect(gateway.callCount, 1);
      expect(useCase.remainingComments, ExplainMonthlyReport.maxCommentsPerSession - 1);
    });

    test('un error no consume cupo', () async {
      final gateway = FakeMonthlyReportGateway.throwing(const LlmGatewayException('quota-exceeded'));
      final useCase = ExplainMonthlyReport(gateway);

      await expectLater(useCase(report: reportOf(2026, 10)), throwsA(isA<LlmGatewayException>()));

      expect(useCase.remainingComments, ExplainMonthlyReport.maxCommentsPerSession);
    });

    test('un timeout tampoco consume cupo', () async {
      final gateway = FakeMonthlyReportGateway.throwing(const LlmGatewayException('timeout'));
      final useCase = ExplainMonthlyReport(gateway);

      await expectLater(
        useCase(report: reportOf(2026, 10)),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'timeout')),
      );

      expect(useCase.remainingComments, ExplainMonthlyReport.maxCommentsPerSession);
    });

    test('un modelo no encontrado (404) tampoco consume cupo', () async {
      final gateway = FakeMonthlyReportGateway.throwing(const LlmGatewayException('model-not-found'));
      final useCase = ExplainMonthlyReport(gateway);

      await expectLater(
        useCase(report: reportOf(2026, 10)),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'model-not-found')),
      );

      expect(useCase.remainingComments, ExplainMonthlyReport.maxCommentsPerSession);
    });
  });

  group('caché en memoria por mes', () {
    test('repetir el mismo mes devuelve el comentario cacheado sin llamar al gateway', () async {
      final gateway = FakeMonthlyReportGateway.returning('Comentario de octubre');
      final useCase = ExplainMonthlyReport(gateway);

      final first = await useCase(report: reportOf(2026, 10));
      final second = await useCase(report: reportOf(2026, 10));

      expect(first, 'Comentario de octubre');
      expect(second, 'Comentario de octubre');
      expect(gateway.callCount, 1);
    });

    test('meses distintos no comparten caché', () async {
      final gateway = FakeMonthlyReportGateway.returning('ok');
      final useCase = ExplainMonthlyReport(gateway);

      await useCase(report: reportOf(2026, 10));
      await useCase(report: reportOf(2026, 9));

      expect(gateway.callCount, 2);
    });

    test('invalida la caché si cambian los movimientos entre dos peticiones del mismo mes', () async {
      final gateway = FakeMonthlyReportGateway.returning('ok');
      final changeNotifier = TransactionsChangeNotifier();
      final useCase = ExplainMonthlyReport(gateway, changeNotifier);

      await useCase(report: reportOf(2026, 10));
      changeNotifier.notifyChanged();
      await useCase(report: reportOf(2026, 10));

      expect(gateway.callCount, 2);
    });
  });

  test('libera la guarda incluso si el gateway falla', () async {
    final gateway = FakeMonthlyReportGateway.throwing(const LlmGatewayException('network-error'));
    final useCase = ExplainMonthlyReport(gateway);

    await expectLater(useCase(report: reportOf(2026, 10)), throwsA(isA<LlmGatewayException>()));

    final gateway2 = FakeMonthlyReportGateway.returning('ok');
    final useCase2 = ExplainMonthlyReport(gateway2);
    expect(await useCase2(report: reportOf(2026, 10)), 'ok');
  });
}
