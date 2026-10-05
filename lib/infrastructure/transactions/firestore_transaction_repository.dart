import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../../domain/transactions/transaction_source.dart';

class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String userId) {
    return _firestore.collection('users').doc(userId).collection('transactions');
  }

  @override
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  }) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);

    return _collection(userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => _fromDocument(doc.id, doc.data())).toList(),
        );
  }

  @override
  String newId({required String userId}) => _collection(userId).doc().id;

  @override
  Future<void> add({
    required String userId,
    required Transaction transaction,
  }) {
    return _collection(userId)
        .doc(transaction.id)
        .set(_toMap(transaction));
  }

  @override
  Future<void> addAll({
    required String userId,
    required List<Transaction> transactions,
  }) {
    final collection = _collection(userId);
    final batch = _firestore.batch();
    for (final transaction in transactions) {
      batch.set(collection.doc(transaction.id), _toMap(transaction));
    }
    return batch.commit();
  }

  @override
  Future<bool> hasDemoData({required String userId}) async {
    final snapshot = await _collection(userId)
        .where('source', isEqualTo: TransactionSource.demo.name)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  @override
  Future<void> update({
    required String userId,
    required Transaction transaction,
  }) {
    return _collection(userId)
        .doc(transaction.id)
        .set(_toMap(transaction));
  }

  @override
  Future<void> delete({
    required String userId,
    required String transactionId,
  }) {
    return _collection(userId).doc(transactionId).delete();
  }

  Map<String, dynamic> _toMap(Transaction transaction) {
    return {
      'amountCents': transaction.amountCents,
      'date': Timestamp.fromDate(transaction.date),
      'description': transaction.description,
      'categoryId': transaction.categoryId.name,
      'source': transaction.source.name,
      'createdAt': Timestamp.fromDate(transaction.createdAt),
    };
  }

  Transaction _fromDocument(String id, Map<String, dynamic> data) {
    return Transaction(
      id: id,
      amountCents: data['amountCents'] as int,
      date: (data['date'] as Timestamp).toDate(),
      description: data['description'] as String,
      categoryId: Category.values.byName(data['categoryId'] as String),
      source: TransactionSource.values.byName(data['source'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
