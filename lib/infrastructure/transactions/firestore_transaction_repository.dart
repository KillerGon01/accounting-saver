import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../../domain/transactions/activity_summary.dart';
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

  /// Usa consultas agregadas (`count` y `sum`), así que no descarga los
  /// movimientos: solo lee el primero y el último por fecha.
  @override
  Future<ActivitySummary> getActivitySummary({required String userId}) async {
    final collection = _collection(userId);

    final total = await collection.count().get();
    final oldest = await collection.orderBy('date').limit(1).get();
    final newest = await collection.orderBy('date', descending: true).limit(1).get();
    final demo = await _countBySource(collection, TransactionSource.demo);
    final manual = await _countBySource(collection, TransactionSource.manual);
    final naturalLanguage = await _countBySource(collection, TransactionSource.naturalLanguage);
    final income = await _sumAmounts(collection, positive: true);
    final expense = await _sumAmounts(collection, positive: false);

    return ActivitySummary(
      totalCount: total.count ?? 0,
      firstDate: _dateOf(oldest),
      lastDate: _dateOf(newest),
      demoCount: demo,
      manualCount: manual,
      naturalLanguageCount: naturalLanguage,
      incomeCents: income,
      expenseCents: -expense,
    );
  }

  /// Único `where` aparte de la igualdad por fecha: ninguno. El rango de
  /// fecha es el único filtro en el servidor, con `orderBy` sobre ese mismo
  /// campo, así que no depende de ningún índice compuesto. Cualquier otro
  /// filtro (categoría, importe, signo...) y toda suma la hace quien llama,
  /// en código, sobre la lista devuelta.
  @override
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  }) async {
    final snapshot = await _collection(userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => _fromDocument(doc.id, doc.data())).toList();
  }

  Future<int> _countBySource(
    CollectionReference<Map<String, dynamic>> collection,
    TransactionSource source,
  ) async {
    final result = await collection
        .where('source', isEqualTo: source.name)
        .count()
        .get();
    return result.count ?? 0;
  }

  /// Suma de los importes positivos (`positive: true`) o de los negativos
  /// (`positive: false`), en céntimos. El paquete devuelve `double`; como los
  /// importes son enteros de céntimos, el redondeo recupera el valor exacto
  /// mientras la suma quede por debajo de 2^53 céntimos.
  Future<int> _sumAmounts(
    Query<Map<String, dynamic>> base, {
    required bool positive,
  }) async {
    final query = positive
        ? base.where('amountCents', isGreaterThan: 0)
        : base.where('amountCents', isLessThan: 0);
    final result = await query
        .aggregate(sum('amountCents'))
        .get();
    return (result.getSum('amountCents') ?? 0).round();
  }

  DateTime? _dateOf(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) return null;
    return (snapshot.docs.first.data()['date'] as Timestamp).toDate();
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
