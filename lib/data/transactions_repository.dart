import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'database_provider.dart';

/// The one place that writes transactions. Screens call this instead of
/// touching the database directly, which keeps the rules in one spot.
class TransactionsRepository {
  TransactionsRepository(this._db);

  final AppDatabase _db;

  Future<String> add({
    required TransactionKind kind,
    required int amountMinor,
    required String currency,
    required DateTime occurredAt,
    String? categoryId,
    String? savingsGoalId,
    String? debtId,
    String? note,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: Value(id),
            kind: kind,
            amountMinor: amountMinor,
            currency: currency,
            occurredAt: occurredAt,
            categoryId: Value(categoryId),
            savingsGoalId: Value(savingsGoalId),
            debtId: Value(debtId),
            note: Value(note),
          ),
        );
    return id;
  }

  Future<void> update(MoneyTransaction tx) => _db
      .update(_db.transactions)
      .replace(tx.copyWith(updatedAt: DateTime.now()));

  /// Puts back a deleted transaction exactly as it was (used by Undo).
  Future<void> restore(MoneyTransaction tx) =>
      _db.into(_db.transactions).insert(tx);

  Future<void> delete(String id) =>
      (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => TransactionsRepository(ref.watch(appDatabaseProvider)),
);
