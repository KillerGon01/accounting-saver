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

      // Real usage: the sample data is loaded the same day the chat is
      // used, in late October, so it covers August, September and
      // October 2026. `recurringExpenses` analyzes the 3 full months
      // *before* the current one (July, August, September): of the
      // generated months, only August and September fall within that
      // range (July has no data, and October is excluded as the current
      // month). That's why each expected recurring expense appears in
      // exactly 2 months, not 3.
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

      // Exactly these 4: no other sample-data expense (weekly groceries,
      // restaurants, electricity, water, gas...) should come out as
      // recurring, because its amount varies each month on purpose.
      expect(byDescription.keys.toSet(), expected.keys.toSet());

      for (final MapEntry(key: description, value: (amountEuros, months)) in expected.entries) {
        final entry = byDescription[description]!;
        expect(entry['amountEuros'], amountEuros, reason: description);
        expect(entry['months'], months, reason: description);
      }
    },
  );
}
