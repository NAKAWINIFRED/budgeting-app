import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';

extension SubscriptionFrequencyLabels on SubscriptionFrequency {
  String get label => switch (this) {
        SubscriptionFrequency.weekly => 'Weekly',
        SubscriptionFrequency.monthly => 'Monthly',
        SubscriptionFrequency.quarterly => 'Every 3 months',
        SubscriptionFrequency.yearly => 'Yearly',
      };

  /// e.g. "$10 a month"
  String get per => switch (this) {
        SubscriptionFrequency.weekly => 'a week',
        SubscriptionFrequency.monthly => 'a month',
        SubscriptionFrequency.quarterly => 'every 3 months',
        SubscriptionFrequency.yearly => 'a year',
      };

  DateTime next(DateTime from) => switch (this) {
        SubscriptionFrequency.weekly => from.add(const Duration(days: 7)),
        SubscriptionFrequency.monthly => addMonths(from, 1),
        SubscriptionFrequency.quarterly => addMonths(from, 3),
        SubscriptionFrequency.yearly => addMonths(from, 12),
      };

  /// Cost converted to an average month.
  int monthlyMinor(int amountMinor) => switch (this) {
        SubscriptionFrequency.weekly => (amountMinor * 52 / 12).round(),
        SubscriptionFrequency.monthly => amountMinor,
        SubscriptionFrequency.quarterly => (amountMinor / 3).round(),
        SubscriptionFrequency.yearly => (amountMinor / 12).round(),
      };
}

extension SubscriptionDue on Subscription {
  int get daysUntilDue => daysFromToday(nextDueDate);
  bool get isOverdue => daysUntilDue < 0;

  /// Due within its reminder window (or already overdue).
  bool get needsAttention => daysUntilDue <= remindDaysBefore;

  String get dueLabel {
    final d = daysUntilDue;
    if (d < -1) return 'Overdue by ${-d} days';
    if (d == -1) return 'Was due yesterday';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    return 'Due in $d days';
  }
}

/// Active subscriptions, soonest due first.
final subscriptionsProvider = StreamProvider<List<Subscription>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.subscriptions)
        ..where((s) => s.isActive.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.nextDueDate)]))
      .watch();
});

class SubscriptionsRepository {
  SubscriptionsRepository(this._db);

  final AppDatabase _db;

  Future<String> add({
    required String name,
    required int amountMinor,
    required String currency,
    required SubscriptionFrequency frequency,
    required DateTime nextDueDate,
    String? purpose,
    String? categoryId,
    PaymentMethod? paymentMethod,
    int remindDaysBefore = 3,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.subscriptions).insert(
          SubscriptionsCompanion.insert(
            id: Value(id),
            name: name,
            purpose: Value(purpose),
            amountMinor: amountMinor,
            currency: currency,
            frequency: frequency,
            nextDueDate: nextDueDate,
            categoryId: Value(categoryId),
            paymentMethod: Value(paymentMethod),
            remindDaysBefore: Value(remindDaysBefore),
          ),
        );
    return id;
  }

  Future<void> update(Subscription s) => _db
      .update(_db.subscriptions)
      .replace(s.copyWith(updatedAt: DateTime.now()));

  Future<void> delete(String id) => _db.transaction(() async {
        await (_db.update(_db.transactions)
              ..where((t) => t.subscriptionId.equals(id)))
            .write(const TransactionsCompanion(subscriptionId: Value(null)));
        await (_db.delete(_db.subscriptions)..where((s) => s.id.equals(id))).go();
      });

  /// Records the payment as an expense and moves the due date forward.
  /// Returns the new transaction's id (for Undo).
  Future<String> markPaid(Subscription s) async {
    final id = const Uuid().v4();
    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: Value(id),
              kind: TransactionKind.expense,
              amountMinor: s.amountMinor,
              currency: s.currency,
              occurredAt: DateTime.now(),
              categoryId: Value(s.categoryId),
              paymentMethod: Value(s.paymentMethod),
              subscriptionId: Value(s.id),
              note: Value(s.name),
            ),
          );
      await update(s.copyWith(nextDueDate: s.frequency.next(s.nextDueDate)));
    });
    return id;
  }

  /// Reverses [markPaid].
  Future<void> undoPaid(Subscription before, String transactionId) =>
      _db.transaction(() async {
        await (_db.delete(_db.transactions)
              ..where((t) => t.id.equals(transactionId)))
            .go();
        await update(before);
      });
}

final subscriptionsRepositoryProvider = Provider<SubscriptionsRepository>(
  (ref) => SubscriptionsRepository(ref.watch(appDatabaseProvider)),
);
