/// Lleva la cuenta de cuántas veces han cambiado los movimientos de un
/// usuario (se ha creado, editado o borrado alguno), para que quien cachee
/// datos derivados de ellos (ver `SendChatMessage`) pueda saber, comparando
/// este contador antes y después, si su caché ha quedado obsoleta.
///
/// También admite observadores (`addListener`/`removeListener`), para
/// quien necesite *reaccionar* al cambio en vez de solo comparar un
/// número más tarde — por ejemplo, un provider de Riverpod que deba
/// recalcular un informe en cuanto cambien los movimientos (ver
/// `transactionsVersionProvider` en la presentación). Sigue siendo Dart
/// puro: `void Function()` es un tipo del lenguaje, no de Flutter ni de
/// ningún paquete de estado.
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
