import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';
import '../activity/activity_providers.dart' show selectedMonthProvider;
import '../dashboard/dashboard_providers.dart';

/// The four expenses pages.
enum ExpenseSection { daily, billsHousing, subscriptions, other }

extension ExpenseSectionX on ExpenseSection {
  String get label => switch (this) {
        ExpenseSection.daily => 'Daily expenses',
        ExpenseSection.billsHousing => 'Bills & housing',
        ExpenseSection.subscriptions => 'Subscriptions',
        ExpenseSection.other => 'Other expenses',
      };

  String get description => switch (this) {
        ExpenseSection.daily =>
          'Everyday spending: food, eating out, transport, little things.',
        ExpenseSection.billsHousing =>
          'Rent, electricity, water, internet, phone.',
        ExpenseSection.subscriptions =>
          'Things you pay for again and again.',
        ExpenseSection.other =>
          'Health, school, family, gifts and everything else.',
      };

  IconData get icon => switch (this) {
        ExpenseSection.daily => Icons.shopping_basket_outlined,
        ExpenseSection.billsHousing => Icons.home_outlined,
        ExpenseSection.subscriptions => Icons.autorenew_rounded,
        ExpenseSection.other => Icons.more_horiz_rounded,
      };

  String get route => switch (this) {
        ExpenseSection.daily => '/expenses/daily',
        ExpenseSection.billsHousing => '/expenses/bills',
        ExpenseSection.subscriptions => '/expenses/subscriptions',
        ExpenseSection.other => '/expenses/other',
      };
}

class CategoryTotal {
  CategoryTotal(this.name, this.iconKey, this.totalMinor);

  final String name;
  final String iconKey;
  final int totalMinor;
}

class SectionData {
  int totalMinor = 0;

  /// Biggest first.
  final List<CategoryTotal> categories = [];

  /// Newest first.
  final List<ActivityItem> items = [];
}

class ExpensesMonth {
  ExpensesMonth(this.sections);

  final Map<ExpenseSection, SectionData> sections;

  int get totalMinor =>
      sections.values.fold(0, (sum, s) => sum + s.totalMinor);
}

/// Which page an expense belongs on.
ExpenseSection sectionOf(MoneyTransaction tx, Map<String, CategoryItem> cats) {
  if (tx.subscriptionId != null) return ExpenseSection.subscriptions;
  return sectionOfCategory(tx.categoryId, cats);
}

/// Which page a category's expenses appear on (no category = Other).
ExpenseSection sectionOfCategory(
  String? categoryId,
  Map<String, CategoryItem> cats,
) {
  final c = cats[categoryId];
  final parent = c?.parentId == null ? c : cats[c!.parentId];
  return switch (parent?.expenseGroup) {
    ExpenseGroup.daily => ExpenseSection.daily,
    ExpenseGroup.billsHousing => ExpenseSection.billsHousing,
    _ => ExpenseSection.other,
  };
}

/// Expenses for the month chosen with the month switcher, split by page.
final expensesMonthProvider = StreamProvider<ExpensesMonth>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final month = ref.watch(selectedMonthProvider);
  final end = DateTime(month.year, month.month + 1);

  return watchTables(
    db,
    [db.transactions, db.categories, db.transactionItems],
    () async {
      final txs = await (db.select(db.transactions)
            ..where(
              (t) =>
                  t.kind.equalsValue(TransactionKind.expense) &
                  t.occurredAt.isBiggerOrEqualValue(month) &
                  t.occurredAt.isSmallerThanValue(end),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.occurredAt),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .get();

      final cats = {for (final c in await db.select(db.categories).get()) c.id: c};
      final items = await describeTransactions(db, txs);

      final sections = {for (final s in ExpenseSection.values) s: SectionData()};
      final catTotals = {
        for (final s in ExpenseSection.values) s: <String, CategoryTotal>{},
      };

      for (final item in items) {
        final tx = item.tx;
        final section = sectionOf(tx, cats);
        final data = sections[section]!;
        data.totalMinor += tx.amountMinor;
        data.items.add(item);

        final c = cats[tx.categoryId];
        final parent = c?.parentId == null ? c : cats[c!.parentId];
        final key = parent?.id ?? 'none';
        final current = catTotals[section]![key];
        catTotals[section]![key] = CategoryTotal(
          parent?.name ?? 'No category',
          parent?.iconKey ?? 'more_horiz',
          (current?.totalMinor ?? 0) + tx.amountMinor,
        );
      }

      for (final s in ExpenseSection.values) {
        sections[s]!.categories
          ..addAll(catTotals[s]!.values)
          ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
      }
      return ExpensesMonth(sections);
    },
  );
});
