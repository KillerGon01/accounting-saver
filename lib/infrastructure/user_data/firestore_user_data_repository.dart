import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/user_data/user_data_repository.dart';

/// Colecciones bajo `users/{uid}` que contienen datos del usuario.
///
/// IMPORTANTE: cualquier colección nueva con datos del usuario debe añadirse
/// aquí. El borrado de cuenta recorre esta lista; si una colección no aparece,
/// sus documentos quedarían huérfanos al eliminar la cuenta de Auth.
const userDataCollections = ['transactions', 'goals'];

/// Límite de Firestore para un `WriteBatch` es 500 operaciones; 400 deja margen.
const _batchSize = 400;

class FirestoreUserDataRepository implements UserDataRepository {
  FirestoreUserDataRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> deleteAllForUser({required String userId}) async {
    final userDoc = _firestore.collection('users').doc(userId);
    for (final name in userDataCollections) {
      await _deleteCollection(userDoc.collection(name));
    }
  }

  /// Borra en lotes hasta que la colección queda vacía. Si se interrumpe, los
  /// documentos ya borrados no vuelven a aparecer y la siguiente llamada
  /// continúa con los que quedan.
  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> collection) async {
    while (true) {
      final snapshot = await collection.limit(_batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
