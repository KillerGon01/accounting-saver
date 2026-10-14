import 'package:accounting_saver/infrastructure/user_data/firestore_user_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'userDataCollections incluye "goals": el borrado de cuenta no debe dejar metas huérfanas '
    'tras un refactor que olvide añadir una colección nueva a esta lista',
    () {
      // Comparación con la lista exacta esperada (no solo "contains"):
      // así, si alguien añade una colección nueva sin querer tocar esta
      // lista, el test también falla y recuerda que hay que decidir si
      // debe borrarse al eliminar la cuenta.
      expect(userDataCollections, ['transactions', 'goals']);
    },
  );
}
