/// Keeps count of how many times a user's transactions have changed
/// (one was created, edited, or deleted), so whoever caches data derived
/// from them (see `SendChatMessage`) can tell, by comparing this counter
/// before and after, whether its cache has gone stale.
///
/// Also supports observers (`addListener`/`removeListener`), for
/// whoever needs to *react* to the change instead of just comparing a
/// number later — for example, a Riverpod provider that needs to
/// recompute a report as soon as the transactions change (see
/// `transactionsVersionProvider` in the presentation layer). Still pure
/// Dart: `void Function()` is a language type, not Flutter's or any
/// state-management package's.
class TransactionsChangeNotifier {
  int _version = 0;
  final _listeners = <void Function()>{};

  int get version => _version;

  void notifyChanged() {
    _version++;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);
}
