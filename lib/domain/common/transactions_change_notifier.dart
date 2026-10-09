/// Lleva la cuenta de cuántas veces han cambiado los movimientos de un
/// usuario (se ha creado, editado o borrado alguno), para que quien cachee
/// datos derivados de ellos (ver `SendChatMessage`) pueda saber, comparando
/// este contador antes y después, si su caché ha quedado obsoleta.
class TransactionsChangeNotifier {
  int _version = 0;

  int get version => _version;

  void notifyChanged() => _version++;
}
