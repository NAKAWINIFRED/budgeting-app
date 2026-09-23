import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/money.dart';
import '../../data/database.dart';

/// Writes every transaction to a CSV file (opens in Excel or Google Sheets)
/// and returns the file's path.
Future<String> exportTransactionsCsv(AppDatabase db) async {
  final txs = await (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .get();
  final categories = {for (final c in await db.select(db.categories).get()) c.id: c};
  final debts = {for (final d in await db.select(db.debts).get()) d.id: d};
  final goals = {for (final g in await db.select(db.savingsGoals).get()) g.id: g};
  final items = await db.select(db.transactionItems).get();
  final itemsByTx = <String, List<TransactionItem>>{};
  for (final i in items) {
    itemsByTx.putIfAbsent(i.transactionId, () => []).add(i);
  }

  String cell(Object? value) {
    final text = value?.toString() ?? '';
    // Quote cells that contain commas, quotes or new lines.
    if (text.contains(RegExp(r'[,"\n]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  String kindLabel(TransactionKind k) => switch (k) {
        TransactionKind.income => 'Income',
        TransactionKind.expense => 'Expense',
        TransactionKind.savingsDeposit => 'Savings deposit',
        TransactionKind.savingsWithdrawal => 'Savings withdrawal',
        TransactionKind.debtPayment => 'Debt payment',
      };

  final rows = <List<Object?>>[
    [
      'Date',
      'Type',
      'Category',
      'Subcategory',
      'Amount',
      'Currency',
      'Paid with',
      'Note',
      'Items',
      'Pay period',
      'Debt',
      'Savings goal',
    ],
  ];

  for (final t in txs) {
    final c = categories[t.categoryId];
    final parent = c?.parentId == null ? c : categories[c!.parentId];
    final sub = c?.parentId == null ? null : c;
    final txItems = itemsByTx[t.id] ?? const <TransactionItem>[];
    final digits = Money.fractionDigits(t.currency);

    rows.add([
      DateFormat('yyyy-MM-dd HH:mm').format(t.occurredAt),
      kindLabel(t.kind),
      parent?.name,
      sub?.name,
      Money.fromMinor(t.amountMinor, t.currency).toStringAsFixed(digits),
      t.currency,
      t.paymentMethod?.name,
      t.note,
      txItems
          .map((i) =>
              '${i.name} ${Money.fromMinor(i.amountMinor, t.currency).toStringAsFixed(digits)}')
          .join('; '),
      t.payPeriod == null ? null : DateFormat('yyyy-MM').format(t.payPeriod!),
      debts[t.debtId]?.name,
      goals[t.savingsGoalId]?.name,
    ]);
  }

  final csv = rows.map((r) => r.map(cell).join(',')).join('\r\n');
  final dir = await getTemporaryDirectory();
  final name = 'tidewise-export-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
  final file = File('${dir.path}/$name');
  // The byte-order mark helps Excel read accents and symbols correctly.
  await file.writeAsString('\uFEFF$csv');
  return file.path;
}
