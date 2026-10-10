import 'package:accounting_saver/domain/common/transactions_change_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionsChangeNotifier', () {
    test('version empieza en 0 y sube uno por cada notifyChanged', () {
      final notifier = TransactionsChangeNotifier();

      expect(notifier.version, 0);
      notifier.notifyChanged();
      expect(notifier.version, 1);
      notifier.notifyChanged();
      expect(notifier.version, 2);
    });

    test('avisa a los listeners registrados en cada notifyChanged', () {
      final notifier = TransactionsChangeNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);

      notifier.notifyChanged();
      notifier.notifyChanged();

      expect(calls, 2);
    });

    test('removeListener deja de avisar a ese listener', () {
      final notifier = TransactionsChangeNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier.addListener(listener);
      notifier.notifyChanged();
      notifier.removeListener(listener);
      notifier.notifyChanged();

      expect(calls, 1);
    });

    test('varios listeners reciben todos el aviso', () {
      final notifier = TransactionsChangeNotifier();
      var firstCalls = 0;
      var secondCalls = 0;
      notifier.addListener(() => firstCalls++);
      notifier.addListener(() => secondCalls++);

      notifier.notifyChanged();

      expect(firstCalls, 1);
      expect(secondCalls, 1);
    });
  });
}
