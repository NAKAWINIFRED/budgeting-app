import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';
import '../dashboard/dashboard_providers.dart' show currentMonthRange;

// ============================================================================
// MODELS
// ============================================================================

class GoalProgress {
  GoalProgress({
    required this.goal,
    required this.depositsMinor,
    required this.withdrawalsMinor,
    required this.thisMonthMinor,
  });

  /// Null means "General savings" (deposits not tied to a goal).
  final SavingsGoal? goal;
  final int depositsMinor;
  final int withdrawalsMinor;

  /// Net added this month (deposits minus withdrawals).
  final int thisMonthMinor;

  String get name => goal?.name ?? 'General savings';
  String get iconKey => goal?.iconKey ?? 'savings';

  int get savedMinor =>
      (goal?.startingAmountMinor ?? 0) + depositsMinor - withdrawalsMinor;

  int? get targetMinor {
    final t = goal?.targetAmountMinor;
    return t == null || t <= 0 ? null : t;
  }

  bool get hasTarget => targetMinor != null;
  bool get isReached => hasTarget && savedMinor >= targetMinor!;

  int? get remainingMinor =>
      hasTarget ? math.max(0, targetMinor! - savedMinor) : null;

  /// 0.0 to 1.0, or null when there is no target.
  double? get progress => hasTarget
      ? (savedMinor / targetMinor!).clamp(0.0, 1.0).toDouble()
      : null;

  /// How much to save each month to hit the target by the target date.
  int? get monthlyNeededMinor {
    final date = goal?.targetDate;
    final remaining = remainingMinor;
    if (date == null || remaining == null || remaining <= 0) return null;
    final now = DateTime.now();
    final months = (date.year - now.year) * 12 + (date.month - now.month);
    if (months < 0) return null;
    return (remaining / math.max(1, months)).ceil();
  }

  bool get isPastDate {
    final date = goal?.targetDate;
    return date != null && !isReached && date.isBefore(DateTime.now());
  }
}

class SavingsOverview {
  SavingsOverview({required this.goals, required this.general});

  /// Active (not archived) goals, oldest first.
  final List<GoalProgress> goals;
  final GoalProgress general;

  List<GoalProgress> get all => [...goals, general];

  int get totalSavedMinor => all.fold(0, (sum, g) => sum + g.savedMinor);
  int get thisMonthMinor => all.fold(0, (sum, g) => sum + g.thisMonthMinor);

  GoalProgress? byId(String? id) =>
      id == null ? general : goals.where((g) => g.goal!.id == id).firstOrNull;
}

// ============================================================================
// PROVIDER
// ============================================================================

final savingsOverviewProvider = StreamProvider<SavingsOverview>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(db, [db.savingsGoals, db.transactions], () async {
    final goals = await (db.select(db.savingsGoals)
          ..where((g) => g.isArchived.equals(false))
          ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
        .get();

    final txs = await (db.select(db.transactions)
          ..where(
            (t) =>
                t.kind.equalsValue(TransactionKind.savingsDeposit) |
                t.kind.equalsValue(TransactionKind.savingsWithdrawal),
          ))
        .get();

    final (start, end) = currentMonthRange();
    final deposits = <String?, int>{};
    final withdrawals = <String?, int>{};
    final month = <String?, int>{};

    for (final t in txs) {
      final key = t.savingsGoalId;
      final isDeposit = t.kind == TransactionKind.savingsDeposit;
      if (isDeposit) {
        deposits[key] = (deposits[key] ?? 0) + t.amountMinor;
      } else {
        withdrawals[key] = (withdrawals[key] ?? 0) + t.amountMinor;
      }
      if (!t.occurredAt.isBefore(start) && t.occurredAt.isBefore(end)) {
        month[key] =
            (month[key] ?? 0) + (isDeposit ? t.amountMinor : -t.amountMinor);
      }
    }

    GoalProgress build(SavingsGoal? g) => GoalProgress(
          goal: g,
          depositsMinor: deposits[g?.id] ?? 0,
          withdrawalsMinor: withdrawals[g?.id] ?? 0,
          thisMonthMinor: month[g?.id] ?? 0,
        );

    return SavingsOverview(
      goals: [for (final g in goals) build(g)],
      general: build(null),
    );
  });
});

// ============================================================================
// REPOSITORY
// ============================================================================

class SavingsRepository {
  SavingsRepository(this._db);

  final AppDatabase _db;

  Future<String> add({
    required String name,
    required SavingsTerm term,
    required String currency,
    required String iconKey,
    int? targetMinor,
    DateTime? targetDate,
    int startingMinor = 0,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.savingsGoals).insert(
          SavingsGoalsCompanion.insert(
            id: Value(id),
            name: name,
            term: term,
            currency: currency,
            iconKey: Value(iconKey),
            targetAmountMinor: Value(targetMinor),
            targetDate: Value(targetDate),
            startingAmountMinor: Value(startingMinor),
          ),
        );
    return id;
  }

  Future<void> update(SavingsGoal goal) => _db
      .update(_db.savingsGoals)
      .replace(goal.copyWith(updatedAt: DateTime.now()));

  /// Deletes a goal. Its deposits and withdrawals are kept and move to
  /// General savings, so no money "disappears" from the totals.
  Future<void> delete(String id) => _db.transaction(() async {
        await (_db.update(_db.transactions)
              ..where((t) => t.savingsGoalId.equals(id)))
            .write(const TransactionsCompanion(savingsGoalId: Value(null)));
        await (_db.delete(_db.savingsGoals)..where((g) => g.id.equals(id)))
            .go();
      });
}

final savingsRepositoryProvider = Provider<SavingsRepository>(
  (ref) => SavingsRepository(ref.watch(appDatabaseProvider)),
);
