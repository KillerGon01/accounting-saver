import 'package:accounting_saver/infrastructure/user_data/firestore_user_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'userDataCollections incluye "goals": el borrado de cuenta no debe dejar metas huérfanas '
    'tras un refactor que olvide añadir una colección nueva a esta lista',
    () {
      // Comparison against the exact expected list (not just "contains"):
      // this way, if someone adds a new collection without meaning to
      // touch this list, the test also fails and reminds them to decide
      // whether it should be deleted when the account is deleted.
      expect(userDataCollections, ['transactions', 'goals']);
    },
  );
}
