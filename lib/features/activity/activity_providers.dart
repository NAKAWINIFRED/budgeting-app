import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
// BREAKDOWN: where the month's money went (or came from), down to each item
// ============================================================================

class BreakdownLine {
  BreakdownLine(this.name, this.amountMinor, this.count, {this.detail});

  final String name;
  final int amountMinor;

  /// How many times it was bought or paid this month.
  final int count;

  /// Extra line under the name, e.g. the date an income arrived.
  final String? detail;
}

class BreakdownGroup {
  BreakdownGroup({
    required this.kind,
    required this.title,
    required this.iconKey,
    required this.totalMinor,
    required this.lines,
  });

  /// Decides the group's color (expense red, income blue, and so on).
  final TransactionKind kind;
  final String title;
  final String iconKey;
  final int totalMinor;
  final List<BreakdownLine> lines;
}

class MonthBreakdown {
  MonthBreakdown(this.groups, this.byMethod);

  /// Biggest first.
  final List<BreakdownGroup> groups;

  /// Totals per payment method (null = not set), biggest first.
  final List<(PaymentMethod?, int)> byMethod;

  int get totalMinor => groups.fold(0, (sum, g) => sum + g.totalMinor);
}

final monthBreakdownProvider = StreamProvider<MonthBreakdown>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final month = ref.watch(selectedMonthProvider);
  return watchTables(
    db,
    [db.transactions, db.transactionItems, db.categories, db.debts, db.savingsGoals],
    () => _loadBreakdown(db, month, income: false),
  );
});

final monthIncomeBreakdownProvider = StreamProvider<MonthBreakdown>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final month = ref.watch(selectedMonthProvider);
  return watchTables(
    db,
    [db.transactions, db.categories],
    () => _loadBreakdown(db, month, income: true),
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

class _GroupBuilder {
  _GroupBuilder(this.kind, this.title, this.iconKey);

  final TransactionKind kind;
  final String title;
  final String iconKey;
  int total = 0;
  bool hasDetail = false;
  final totals = _LineTotals();
  final entries = <(DateTime, BreakdownLine)>[];
}

Future<MonthBreakdown> _loadBreakdown(
  AppDatabase db,
  DateTime month, {
  required bool income,
}) async {
  final end = DateTime(month.year, month.month + 1);
  final txs = await (db.select(db.transactions)
        ..where(
          (t) =>
              t.occurredAt.isBiggerOrEqualValue(month) &
              t.occurredAt.isSmallerThanValue(end),
        ))
      .get();

  final wanted = income
      ? {TransactionKind.income}
      : {
          TransactionKind.expense,
          TransactionKind.debtPayment,
          TransactionKind.savingsDeposit,
        };
  final selected = txs.where((t) => wanted.contains(t.kind)).toList();

  final categories = {
    for (final c in await db.select(db.categories).get()) c.id: c,
  };
  final debts = {for (final d in await db.select(db.debts).get()) d.id: d};
  final goals = {
    for (final g in await db.select(db.savingsGoals).get()) g.id: g,
  };

  final ids = [for (final t in selected) t.id];
  final items = income || ids.isEmpty
      ? <TransactionItem>[]
      : await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.isIn(ids)))
          .get();
  final itemsByTx = <String, List<TransactionItem>>{};
  for (final i in items) {
    itemsByTx.putIfAbsent(i.transactionId, () => []).add(i);
  }

  final groups = <String, _GroupBuilder>{};
  _GroupBuilder group(
    TransactionKind kind,
    String key,
    String title,
    String iconKey,
  ) =>
      groups.putIfAbsent(key, () => _GroupBuilder(kind, title, iconKey));

  final byMethod = <PaymentMethod?, int>{};

  for (final tx in selected) {
    byMethod[tx.paymentMethod] = (byMethod[tx.paymentMethod] ?? 0) + tx.amountMinor;

    switch (tx.kind) {
      case TransactionKind.income:
      case TransactionKind.expense:
        // Group by the top-level category; subcategories become lines.
        final category = categories[tx.categoryId];
        final parent =
            category?.parentId == null ? category : categories[category!.parentId];
        final sub = category?.parentId == null ? null : category;
        final g = group(
          tx.kind,
          'cat:${parent?.id}',
          parent?.name ?? (income ? 'Income' : 'Other'),
          parent?.iconKey ?? 'more_horiz',
        );
        g.total += tx.amountMinor;

        if (income) {
          // Income: list each payment with its date (and pay period).
          final period = tx.payPeriod;
          final detail = [
            DateFormat.MMMd().format(tx.occurredAt),
            if (period != null) 'for ${payPeriodLabel(period, tx.occurredAt)}',
          ].join(', ');
          final note = tx.note;
          g.entries.add((
            tx.occurredAt,
            BreakdownLine(
              sub?.name ?? (note != null && note.isNotEmpty ? note : g.title),
              tx.amountMinor,
              1,
              detail: detail,
            ),
          ));
          g.hasDetail = true;
        } else {
          final txItems = itemsByTx[tx.id] ?? const <TransactionItem>[];
          if (txItems.isNotEmpty) {
            var itemizedSum = 0;
            for (final i in txItems) {
              g.totals.add(i.name, i.amountMinor);
              itemizedSum += i.amountMinor;
            }
            final rest = tx.amountMinor - itemizedSum;
            if (rest > 0) g.totals.add(sub?.name ?? 'Not broken down', rest);
            g.hasDetail = true;
          } else if (sub != null) {
            g.totals.add(sub.name, tx.amountMinor);
            g.hasDetail = true;
          } else {
            g.totals.add('Not broken down', tx.amountMinor);
          }
        }
      case TransactionKind.debtPayment:
        final g = group(tx.kind, 'debts', 'Debt payments', 'payments');
        g.total += tx.amountMinor;
        g.totals.add(debts[tx.debtId]?.name ?? 'Debt', tx.amountMinor);
        g.hasDetail = true;
      case TransactionKind.savingsDeposit:
        final g = group(tx.kind, 'savings', 'Savings', 'savings');
        g.total += tx.amountMinor;
        g.totals.add(
          goals[tx.savingsGoalId]?.name ?? 'General savings',
          tx.amountMinor,
        );
        g.hasDetail = true;
      case TransactionKind.savingsWithdrawal:
        break;
    }
  }

  final result = [
    for (final g in groups.values)
      BreakdownGroup(
        kind: g.kind,
        title: g.title,
        iconKey: g.iconKey,
        totalMinor: g.total,
        // Only show lines when there is something more specific to show.
        lines: !g.hasDetail
            ? const []
            : income
                ? ([...g.entries]..sort((a, b) => b.$1.compareTo(a.$1)))
                    .map((e) => e.$2)
                    .toList()
                : g.totals.toLines(),
      ),
  ]..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

  final methods = byMethod.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return MonthBreakdown(result, methods);
}
