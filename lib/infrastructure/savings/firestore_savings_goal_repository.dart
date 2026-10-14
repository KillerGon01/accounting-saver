import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

class FirestoreSavingsGoalRepository implements SavingsGoalRepository {
  FirestoreSavingsGoalRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String userId) {
    return _firestore.collection('users').doc(userId).collection('goals');
  }

  @override
  Stream<List<SavingsGoal>> watchAll({required String userId}) {
    return _collection(userId)
        .orderBy('deadline')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => _fromDocument(doc.id, doc.data())).toList());
  }

  @override
  String newId({required String userId}) => _collection(userId).doc().id;

  @override
  Future<void> add({required String userId, required SavingsGoal goal}) {
    return _collection(userId).doc(goal.id).set(_toMap(goal));
  }

  @override
  Future<void> update({required String userId, required SavingsGoal goal}) {
    return _collection(userId).doc(goal.id).set(_toMap(goal));
  }

  @override
  Future<void> delete({required String userId, required String goalId}) {
    return _collection(userId).doc(goalId).delete();
  }

  @override
  Future<int> count({required String userId}) async {
    final result = await _collection(userId).count().get();
    return result.count ?? 0;
  }

  Map<String, dynamic> _toMap(SavingsGoal goal) {
    return {
      'name': goal.name,
      'targetCents': goal.targetCents,
      'savedCents': goal.savedCents,
      'deadline': Timestamp.fromDate(goal.deadline),
      'createdAt': Timestamp.fromDate(goal.createdAt),
    };
  }

  SavingsGoal _fromDocument(String id, Map<String, dynamic> data) {
    return SavingsGoal(
      id: id,
      name: data['name'] as String,
      targetCents: data['targetCents'] as int,
      savedCents: data['savedCents'] as int,
      deadline: (data['deadline'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
