import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';

// ============================================================================
// MODELS
// ============================================================================

class BucketProgress {
  BucketProgress({
    required this.bucket,
    required this.allocatedMinor,
    required this.usedMinor,
  });

  final BudgetBucket bucket;
  final int allocatedMinor;
  final int usedMinor;

  double get ratio => allocatedMinor <= 0 ? 0 : usedMinor / allocatedMinor;

  /// Positive = room left (or still to save); negative = over the plan.
  int get remainingMinor => allocatedMinor - usedMinor;

  /// Savings and debt buckets are good to go over; spending buckets are not.
  bool get isGoodWhenOver => bucket.tagList.every(
        (t) =>
            t == BudgetTag.longTermSavings ||
            t == BudgetTag.shortTermSavings ||
            t == BudgetTag.debt,
      );
}

class DashboardSummary {
  DashboardSummary({
    required this.currency,
    required this.incomeMinor,
    required this.outflowMinor,
    required this.strategy,
    required this.buckets,
    required this.categories,
    required this.spentByCategory,
  });

  final String currency;
  final int incomeMinor;

  /// Spending + savings deposits + debt payments, minus savings withdrawals.
  final int outflowMinor;
  final BudgetStrategy? strategy;
  final List<BucketProgress> buckets;
  final Map<String, CategoryItem> categories;

  /// This month's spending per category id.
  final Map<String, int> spentByCategory;

  int get safeToSpendMinor => incomeMinor - outflowMinor;

  /// Tide level from 0 (empty) to 1 (nothing spent yet).
  double get level => incomeMinor <= 0
      ? 0
      : (safeToSpendMinor / incomeMinor).clamp(0.0, 1.0).toDouble();
}

class ActivityItem {
  ActivityItem({required this.tx, required this.title, required this.iconKey});

  final MoneyTransaction tx;
  final String title;
  final String iconKey;

  bool get isIncoming =>
      tx.kind == TransactionKind.income ||
      tx.kind == TransactionKind.savingsWithdrawal;
}

// ============================================================================
// PROVIDERS
// These are streams: whenever a transaction is added, edited or deleted,
// the home screen updates by itself.
// ============================================================================

(DateTime, DateTime) currentMonthRange() {
  final now = DateTime.now();
  return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
}

final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) {
  final db = ref.watch(appDatabaseProvider);

  // Recalculates when transactions change AND when the user switches plans.
  return watchTables(
    db,
    [
      db.transactions,
      db.budgetStrategies,
      db.budgetBuckets,
      db.categories,
      db.savingsGoals,
    ],
    () async {
      final (start, end) = currentMonthRange();
      final txs = await (db.select(db.transactions)
            ..where(
              (t) =>
                  t.occurredAt.isBiggerOrEqualValue(start) &
                  t.occurredAt.isSmallerThanValue(end),
            ))
          .get();
      return _buildSummary(db, txs);
    },
  );
});

final recentActivityProvider = StreamProvider<List<ActivityItem>>((ref) {
  final db = ref.watch(appDatabaseProvider);

  final query = db.select(db.transactions)
    ..orderBy([
      (t) => OrderingTerm.desc(t.occurredAt),
      (t) => OrderingTerm.desc(t.createdAt),
    ])
    ..limit(6);

  return query.watch().asyncMap((txs) => describeTransactions(db, txs));
});

/// Turns raw transactions into display-ready items (title + icon).
Future<List<ActivityItem>> describeTransactions(
  AppDatabase db,
  List<MoneyTransaction> txs,
) async {
  final categories = {
    for (final c in await db.select(db.categories).get()) c.id: c,
  };
  final goals = {
    for (final g in await db.select(db.savingsGoals).get()) g.id: g,
  };
  final debts = {for (final d in await db.select(db.debts).get()) d.id: d};

  return [for (final tx in txs) _describe(tx, categories, goals, debts)];
}

// ============================================================================
// CALCULATIONS
// ============================================================================

Future<DashboardSummary> _buildSummary(
  AppDatabase db,
  List<MoneyTransaction> txs,
) async {
  final categories = {
    for (final c in await db.select(db.categories).get()) c.id: c,
  };
  final goals = {
    for (final g in await db.select(db.savingsGoals).get()) g.id: g,
  };

  final strategy = await (db.select(db.budgetStrategies)
        ..where((s) => s.isActive.equals(true))
        ..limit(1))
      .getSingleOrNull();

  final buckets = strategy == null
      ? <BudgetBucket>[]
      : await (db.select(db.budgetBuckets)
            ..where((b) => b.strategyId.equals(strategy.id))
            ..orderBy([(b) => OrderingTerm.asc(b.sortOrder)]))
          .get();

  var income = 0;
  var outflow = 0;
  final usedByTag = {for (final t in BudgetTag.values) t: 0};
  final spentByCategory = <String, int>{};

  // NOTE: assumes one currency for now. Multi-currency comes later.
  for (final tx in txs) {
    final amount = tx.amountMinor;
    switch (tx.kind) {
      case TransactionKind.income:
        income += amount;
      case TransactionKind.expense:
        outflow += amount;
        final tag = categories[tx.categoryId]?.budgetTag ?? BudgetTag.wants;
        usedByTag[tag] = usedByTag[tag]! + amount;
        final categoryId = tx.categoryId;
        if (categoryId != null) {
          spentByCategory[categoryId] =
              (spentByCategory[categoryId] ?? 0) + amount;
        }
      case TransactionKind.savingsDeposit:
        outflow += amount;
        final tag = _savingsTag(goals[tx.savingsGoalId]);
        usedByTag[tag] = usedByTag[tag]! + amount;
      case TransactionKind.savingsWithdrawal:
        outflow -= amount;
        final tag = _savingsTag(goals[tx.savingsGoalId]);
        usedByTag[tag] = usedByTag[tag]! - amount;
      case TransactionKind.debtPayment:
        outflow += amount;
        usedByTag[BudgetTag.debt] = usedByTag[BudgetTag.debt]! + amount;
    }
  }

  return DashboardSummary(
    currency: kDefaultCurrency,
    incomeMinor: income,
    outflowMinor: outflow,
    strategy: strategy,
    categories: categories,
    spentByCategory: spentByCategory,
    buckets: [
      for (final b in buckets)
        BucketProgress(
          bucket: b,
          allocatedMinor: Money.share(income, b.basisPoints),
          usedMinor: b.tagList.fold(0, (sum, t) => sum + usedByTag[t]!),
        ),
    ],
  );
}

BudgetTag _savingsTag(SavingsGoal? goal) => goal?.term == SavingsTerm.longTerm
    ? BudgetTag.longTermSavings
    : BudgetTag.shortTermSavings;

ActivityItem _describe(
  MoneyTransaction tx,
  Map<String, CategoryItem> categories,
  Map<String, SavingsGoal> goals,
  Map<String, Debt> debts,
) {
  final category = categories[tx.categoryId];
  switch (tx.kind) {
    case TransactionKind.savingsDeposit:
      final goal = goals[tx.savingsGoalId];
      return ActivityItem(
        tx: tx,
        title: 'Saved to ${goal?.name ?? 'savings'}',
        iconKey: 'savings',
      );
    case TransactionKind.savingsWithdrawal:
      final goal = goals[tx.savingsGoalId];
      return ActivityItem(
        tx: tx,
        title: 'Took from ${goal?.name ?? 'savings'}',
        iconKey: 'savings',
      );
    case TransactionKind.debtPayment:
      final debt = debts[tx.debtId];
      return ActivityItem(
        tx: tx,
        title: 'Paid ${debt?.name ?? 'debt'}',
        iconKey: 'payments',
      );
    case TransactionKind.income:
      return ActivityItem(
        tx: tx,
        title: category?.name ?? 'Income',
        iconKey: category?.iconKey ?? 'work',
      );
    case TransactionKind.expense:
      return ActivityItem(
        tx: tx,
        title: category?.name ?? 'Expense',
        iconKey: category?.iconKey ?? 'more_horiz',
      );
  }
}
