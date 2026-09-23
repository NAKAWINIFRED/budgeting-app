import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'database_provider.dart';

/// One line of an itemized expense before it is saved.
class ItemDraft {
  const ItemDraft(this.name, this.amountMinor);

  final String name;
  final int amountMinor;
}

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
    List<ItemDraft> items = const [],
  }) async {
    final id = const Uuid().v4();
    await _db.transaction(() async {
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
      await _insertItems(id, items);
    });
    return id;
  }

  /// Saves changes. Pass [items] to replace the transaction's items
  /// (an empty list removes them); leave it null to keep them as they are.
  Future<void> update(MoneyTransaction tx, {List<ItemDraft>? items}) {
    return _db.transaction(() async {
      await _db
          .update(_db.transactions)
          .replace(tx.copyWith(updatedAt: DateTime.now()));
      if (items != null) {
        await (_db.delete(_db.transactionItems)
              ..where((i) => i.transactionId.equals(tx.id)))
            .go();
        await _insertItems(tx.id, items);
      }
    });
  }

  Future<List<TransactionItem>> itemsFor(String transactionId) {
    return (_db.select(_db.transactionItems)
          ..where((i) => i.transactionId.equals(transactionId))
          ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
        .get();
  }

  /// Deleting a transaction also deletes its items automatically.
  Future<void> delete(String id) =>
      (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();

  /// Puts back a deleted transaction and its items exactly as they were.
  Future<void> restore(MoneyTransaction tx, [List<TransactionItem> items = const []]) {
    return _db.transaction(() async {
      await _db.into(_db.transactions).insert(tx);
      for (final item in items) {
        await _db.into(_db.transactionItems).insert(item);
      }
    });
  }

  Future<void> _insertItems(String transactionId, List<ItemDraft> items) async {
    for (var i = 0; i < items.length; i++) {
      await _db.into(_db.transactionItems).insert(
            TransactionItemsCompanion.insert(
              transactionId: transactionId,
              name: items[i].name,
              amountMinor: items[i].amountMinor,
              sortOrder: Value(i),
            ),
          );
    }
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => TransactionsRepository(ref.watch(appDatabaseProvider)),
);
