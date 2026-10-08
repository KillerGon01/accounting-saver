import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/domain/chat/chat_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_transaction_repository.dart';

void main() {
  test('recurringExpenses detecta Netflix, Spotify y Gimnasio en los datos de ejemplo', () async {
    const userId = 'u1';
    final repository = FakeTransactionRepository();

    // Los datos de ejemplo se cargaron "antes" (a finales de septiembre),
    // así que cubren julio, agosto y septiembre de 2026 completos. El chat
    // se usa más tarde, en octubre: FakeClock fija esa fecha para
    // recurringExpenses, cuyo rango de 3 meses completos coincide
    // exactamente con julio-agosto-septiembre.
    await LoadDemoData(repository)(userId: userId, now: DateTime(2026, 9, 30));
    final clock = FakeClock(DateTime(2026, 10, 9));

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

    // Alquiler también es un cargo fijo de los datos de ejemplo, así que
    // también saldrá como recurrente: no se exige que la lista tenga
    // exactamente estos tres, solo que estén presentes con lo esperado.
    const expected = {
      'netflix': ('12,99', ['2026-07', '2026-08', '2026-09']),
      'spotify': ('10,99', ['2026-07', '2026-08', '2026-09']),
      'gimnasio': ('35,00', ['2026-07', '2026-08', '2026-09']),
    };
    for (final MapEntry(key: description, value: (amountEuros, months)) in expected.entries) {
      final entry = byDescription[description];
      expect(entry, isNotNull, reason: description);
      expect(entry!['amountEuros'], amountEuros, reason: description);
      expect(entry['months'], months, reason: description);
    }
  });
}
