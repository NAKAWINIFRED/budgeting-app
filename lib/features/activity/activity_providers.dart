import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../dashboard/dashboard_providers.dart';

// ============================================================================
// FILTERS
// ============================================================================

enum ActivityFilter { all, income, expenses, savings, debt }

extension ActivityFilterX on ActivityFilter {
  String get label => switch (this) {
        ActivityFilter.all => 'All',
        ActivityFilter.income => 'Income',
        ActivityFilter.expenses => 'Expenses',
        ActivityFilter.savings => 'Savings',
        ActivityFilter.debt => 'Debt',
      };

  bool matches(ActivityItem item) => switch (this) {
        ActivityFilter.all => true,
        ActivityFilter.income => item.tx.kind == TransactionKind.income,
        ActivityFilter.expenses => item.tx.kind == TransactionKind.expense,
        ActivityFilter.savings =>
          item.tx.kind == TransactionKind.savingsDeposit ||
              item.tx.kind == TransactionKind.savingsWithdrawal,
        ActivityFilter.debt => item.tx.kind == TransactionKind.debtPayment,
      };
}

class ActivityFilterNotifier extends Notifier<ActivityFilter> {
  @override
  ActivityFilter build() => ActivityFilter.all;

  void select(ActivityFilter filter) => state = filter;
}

final activityFilterProvider =
    NotifierProvider<ActivityFilterNotifier, ActivityFilter>(
  ActivityFilterNotifier.new,
);

// ============================================================================
// MONTH
// ============================================================================

class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void previous() => state = DateTime(state.year, state.month - 1);
  void next() => state = DateTime(state.year, state.month + 1);
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, DateTime>(
  SelectedMonthNotifier.new,
);

// ============================================================================
// DATA
// ============================================================================

class MonthActivity {
  MonthActivity(this.items);

  /// Newest first.
  final List<ActivityItem> items;

  int _sum(bool Function(TransactionKind k) test) => items
      .where((i) => test(i.tx.kind))
      .fold(0, (sum, i) => sum + i.tx.amountMinor);

  int get inMinor => _sum((k) => k == TransactionKind.income);

  int get outMinor => _sum(
        (k) => k == TransactionKind.expense || k == TransactionKind.debtPayment,
      );

  int get savedMinor =>
      _sum((k) => k == TransactionKind.savingsDeposit) -
      _sum((k) => k == TransactionKind.savingsWithdrawal);
}

final monthActivityProvider = StreamProvider<MonthActivity>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final month = ref.watch(selectedMonthProvider);
  final end = DateTime(month.year, month.month + 1);

  final query = db.select(db.transactions)
    ..where(
      (t) =>
          t.occurredAt.isBiggerOrEqualValue(month) &
          t.occurredAt.isSmallerThanValue(end),
    )
    ..orderBy([
      (t) => OrderingTerm.desc(t.occurredAt),
      (t) => OrderingTerm.desc(t.createdAt),
    ]);

  return query
      .watch()
      .asyncMap((txs) async => MonthActivity(await describeTransactions(db, txs)));
});
