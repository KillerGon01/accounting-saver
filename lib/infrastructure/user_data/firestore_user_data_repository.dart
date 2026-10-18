import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/user_data/user_data_repository.dart';

/// Collections under `users/{uid}` that hold the user's data.
///
/// IMPORTANT: any new collection with user data must be added here.
/// Account deletion walks this list; if a collection doesn't appear,
/// its documents would be left orphaned when the Auth account is
/// deleted.
const userDataCollections = ['transactions', 'goals'];

/// Firestore's limit for a `WriteBatch` is 500 operations; 400 leaves margin.
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

  /// Deletes in batches until the collection is empty. If interrupted,
  /// the documents already deleted don't come back and the next call
  /// continues with the ones left.
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
