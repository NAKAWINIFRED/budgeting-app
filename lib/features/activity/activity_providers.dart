import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';
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

// ============================================================================
// BREAKDOWN: where the month's money went, down to each item
// ============================================================================

class BreakdownLine {
  BreakdownLine(this.name, this.amountMinor, this.count);

  final String name;
  final int amountMinor;

  /// How many times it was bought or paid this month.
  final int count;
}

class BreakdownGroup {
  BreakdownGroup({
    required this.title,
    required this.iconKey,
    required this.totalMinor,
    required this.lines,
  });

  final String title;
  final String iconKey;
  final int totalMinor;
  final List<BreakdownLine> lines;
}

class MonthBreakdown {
  MonthBreakdown(this.groups);

  /// Biggest first.
  final List<BreakdownGroup> groups;

  int get totalMinor => groups.fold(0, (sum, g) => sum + g.totalMinor);
}

final monthBreakdownProvider = StreamProvider<MonthBreakdown>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final month = ref.watch(selectedMonthProvider);
  return watchTables(
    db,
    [
      db.transactions,
      db.transactionItems,
      db.categories,
      db.debts,
      db.savingsGoals,
    ],
    () => _loadBreakdown(db, month),
  );
});

/// Collects amounts per line name inside one group (case-insensitive).
class _LineTotals {
  final _lines = <String, (String, int, int)>{};

  void add(String name, int amount) {
    final key = name.trim().toLowerCase();
    final current = _lines[key];
    _lines[key] = current == null
        ? (name.trim(), amount, 1)
        : (current.$1, current.$2 + amount, current.$3 + 1);
  }

  List<BreakdownLine> toLines() => _lines.values
      .map((l) => BreakdownLine(l.$1, l.$2, l.$3))
      .toList()
    ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
}

Future<MonthBreakdown> _loadBreakdown(AppDatabase db, DateTime month) async {
  final end = DateTime(month.year, month.month + 1);
  final txs = await (db.select(db.transactions)
        ..where(
          (t) =>
              t.occurredAt.isBiggerOrEqualValue(month) &
              t.occurredAt.isSmallerThanValue(end),
        ))
      .get();

  final outflows = txs
      .where(
        (t) =>
            t.kind == TransactionKind.expense ||
            t.kind == TransactionKind.debtPayment ||
            t.kind == TransactionKind.savingsDeposit,
      )
      .toList();

  final categories = {
    for (final c in await db.select(db.categories).get()) c.id: c,
  };
  final debts = {for (final d in await db.select(db.debts).get()) d.id: d};
  final goals = {
    for (final g in await db.select(db.savingsGoals).get()) g.id: g,
  };

  final ids = [for (final t in outflows) t.id];
  final items = ids.isEmpty
      ? <TransactionItem>[]
      : await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.isIn(ids)))
          .get();
  final itemsByTx = <String, List<TransactionItem>>{};
  for (final i in items) {
    itemsByTx.putIfAbsent(i.transactionId, () => []).add(i);
  }

  // key -> (title, iconKey, total, line totals, has any itemized entries)
  final groups = <String, (String, String, int, _LineTotals, bool)>{};

  void addTo(
    String key,
    String title,
    String iconKey,
    int amount,
    void Function(_LineTotals lines) fill, {
    bool itemized = false,
  }) {
    final g = groups[key] ?? (title, iconKey, 0, _LineTotals(), false);
    fill(g.$4);
    groups[key] = (g.$1, g.$2, g.$3 + amount, g.$4, g.$5 || itemized);
  }

  for (final tx in outflows) {
    switch (tx.kind) {
      case TransactionKind.expense:
        final category = categories[tx.categoryId];
        final txItems = itemsByTx[tx.id] ?? const <TransactionItem>[];
        addTo(
          'cat:${tx.categoryId}',
          category?.name ?? 'Other',
          category?.iconKey ?? 'more_horiz',
          tx.amountMinor,
          itemized: txItems.isNotEmpty,
          (lines) {
            var itemizedSum = 0;
            for (final i in txItems) {
              lines.add(i.name, i.amountMinor);
              itemizedSum += i.amountMinor;
            }
            final rest = tx.amountMinor - itemizedSum;
            if (rest > 0) lines.add('Not broken down', rest);
          },
        );
      case TransactionKind.debtPayment:
        addTo(
          'debts',
          'Debt payments',
          'payments',
          tx.amountMinor,
          itemized: true,
          (lines) => lines.add(debts[tx.debtId]?.name ?? 'Debt', tx.amountMinor),
        );
      case TransactionKind.savingsDeposit:
        addTo(
          'savings',
          'Savings',
          'savings',
          tx.amountMinor,
          itemized: true,
          (lines) => lines.add(
            goals[tx.savingsGoalId]?.name ?? 'General savings',
            tx.amountMinor,
          ),
        );
      default:
        break;
    }
  }

  final result = [
    for (final g in groups.values)
      BreakdownGroup(
        title: g.$1,
        iconKey: g.$2,
        totalMinor: g.$3,
        // Only show lines when something in the group was broken down.
        lines: g.$5 ? g.$4.toLines() : const [],
      ),
  ]..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

  return MonthBreakdown(result);
}
