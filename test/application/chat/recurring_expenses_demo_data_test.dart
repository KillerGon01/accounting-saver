import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/domain/chat/chat_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_transaction_repository.dart';

void main() {
  test(
    'recurringExpenses detecta exactamente Alquiler, Gimnasio, Netflix y Spotify con el uso real',
    () async {
      const userId = 'u1';
      final repository = FakeTransactionRepository();

      // Uso real: los datos de ejemplo se cargan el mismo día en que se usa
      // el chat, a finales de octubre, así que cubren agosto, septiembre y
      // octubre de 2026. `recurringExpenses` analiza los 3 meses completos
      // *anteriores* al actual (julio, agosto, septiembre): de los meses
      // generados, solo agosto y septiembre caen dentro de ese rango (julio
      // no tiene datos, y octubre queda fuera por ser el mes en curso). Por
      // eso cada recurrente esperado aparece en exactamente 2 meses, no 3.
      final now = DateTime(2026, 10, 31);
      await LoadDemoData(repository)(userId: userId, now: now);
      final clock = FakeClock(now);

      final result = await TransactionChatFunctions(repository).execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: clock.now(),
      );

      expect(result['desde'], '2026-07-01');
      expect(result['hasta'], '2026-09-30');

      final recurring = result['recurringExpenses'] as List<dynamic>;
      final byDescription = <String, Map<Object?, Object?>>{
        for (final entry in recurring) (entry as Map)['description'] as String: entry,
      };

      const expected = {
        'alquiler': ('850,00', ['2026-08', '2026-09']),
        'gimnasio': ('35,00', ['2026-08', '2026-09']),
        'netflix': ('12,99', ['2026-08', '2026-09']),
        'spotify': ('10,99', ['2026-08', '2026-09']),
      };

      // Exactamente estos 4: ningún otro gasto de los datos de ejemplo
      // (compra semanal, restaurantes, luz, agua, gasolina...) debe salir
      // como recurrente, porque su importe varía cada mes a propósito.
      expect(byDescription.keys.toSet(), expected.keys.toSet());

      for (final MapEntry(key: description, value: (amountEuros, months)) in expected.entries) {
        final entry = byDescription[description]!;
        expect(entry['amountEuros'], amountEuros, reason: description);
        expect(entry['months'], months, reason: description);
      }
    },
  );
}
