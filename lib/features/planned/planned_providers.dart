import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';

/// Items planned for one month (pass the month's first day), in order.
final plannedExpensesProvider =
    StreamProvider.family<List<PlannedExpense>, DateTime>((ref, month) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.plannedExpenses)
        ..where((p) => p.forMonth.equals(month))
        ..orderBy([
          (p) => OrderingTerm.asc(p.sortOrder),
          (p) => OrderingTerm.asc(p.createdAt),
        ]))
      .watch();
});

/// Totals for a month's list.
class PlannedSummary {
  PlannedSummary(List<PlannedExpense> items)
      : pending = items.where((i) => !i.isDone).toList(),
        done = items.where((i) => i.isDone).toList();

  final List<PlannedExpense> pending;
  final List<PlannedExpense> done;

  /// Still to buy (items with a price).
  int get remainingMinor => pending.fold(0, (s, i) => s + (i.amountMinor ?? 0));

  /// Already bought.
  int get clearedMinor => done.fold(0, (s, i) => s + (i.amountMinor ?? 0));

  int get totalMinor => remainingMinor + clearedMinor;
  int get unpricedCount => pending.where((i) => i.amountMinor == null).length;
  bool get isEmpty => pending.isEmpty && done.isEmpty;
}

// ============================================================================
// QUICK ENTRY: "water 50, wifi: 20, rice, 2kg sugar 30"
// ============================================================================

class DraftItem {
  DraftItem(this.name, this.amountMinor);

  final String name;
  final int? amountMinor;
}

List<DraftItem> parseQuickList(String input) {
  // Split on new lines, semicolons, and commas that are not thousands
  // separators (so "rent 1,500" stays one item).
  final parts = input.split(RegExp(r'[;\n]|,(?!\d{3}(?!\d))'));
  final result = <DraftItem>[];
  final pattern = RegExp(r'^(.*?)[\s:=\-]*(\d[\d,]*(?:\.\d+)?)?\s*$');

  for (final raw in parts) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    final m = pattern.firstMatch(text);
    var name = (m?.group(1) ?? text).trim();
    final number = m?.group(2);
    if (name.isEmpty) {
      // Just a number on its own: keep it as the name.
      name = text;
    }
    final amount = number == null
        ? null
        : parseAmountMinor(number.replaceAll(',', ''), kDefaultCurrency);
    result.add(
      DraftItem(
        name[0].toUpperCase() + name.substring(1),
        amount != null && amount > 0 ? amount : null,
      ),
    );
  }
  return result;
}

// ============================================================================
// CATEGORY GUESSING
// ============================================================================

/// Common words -> category (and optional subcategory) names.
final _keywords = <String, (String, String?)>{
  // Bills
  'electricity': ('Bills & Utilities', 'Electricity'),
  'power': ('Bills & Utilities', 'Electricity'),
  'cashpower': ('Bills & Utilities', 'Electricity'),
  'water': ('Bills & Utilities', 'Water'),
  'wifi': ('Bills & Utilities', 'Internet & Wifi'),
  'internet': ('Bills & Utilities', 'Internet & Wifi'),
  'gas': ('Bills & Utilities', 'Cooking gas'),
  'tv': ('Bills & Utilities', null),
  'dstv': ('Bills & Utilities', null),
  'canal': ('Bills & Utilities', null),
  'airtime': ('Phone & Internet', null),
  'data': ('Phone & Internet', null),
  'bundle': ('Phone & Internet', null),
  'phone': ('Phone & Internet', null),
  // Housing
  'rent': ('Housing & Rent', null),
  'house': ('Housing & Rent', null),
  // Groceries
  for (final w in const [
    'rice', 'eggs', 'egg', 'milk', 'bread', 'sugar', 'flour', 'oil', 'meat',
    'beef', 'chicken', 'fish', 'vegetables', 'veggies', 'fruit', 'fruits',
    'beans', 'maize', 'salt', 'tea', 'coffee', 'butter', 'cheese', 'tomatoes',
    'onions', 'potatoes', 'bananas', 'matoke', 'cassava', 'pasta', 'spaghetti',
    'groceries', 'food', 'juice', 'yogurt', 'cereal', 'peanut', 'avocado',
  ])
    w: ('Groceries', null),
  // Home supplies
  for (final w in const [
    'soap', 'detergent', 'toilet', 'tissue', 'toothpaste', 'bleach', 'sponge',
    'candles', 'broom', 'mop', 'cleaning', 'dish', 'bulb', 'batteries',
  ])
    w: ('Home Supplies', null),
  // Transport
  for (final w in const [
    'fuel', 'petrol', 'diesel', 'bus', 'taxi', 'moto', 'fare', 'transport',
    'uber', 'bolt', 'parking',
  ])
    w: ('Transport', null),
  // Health
  for (final w in const [
    'medicine', 'pharmacy', 'doctor', 'hospital', 'clinic', 'insurance',
    'pills', 'dentist',
  ])
    w: ('Health', null),
  // Education
  for (final w in const [
    'school', 'fees', 'tuition', 'books', 'uniform', 'stationery',
  ])
    w: ('Education', null),
  // Personal care
  for (final w in const [
    'haircut', 'salon', 'lotion', 'shampoo', 'barber', 'perfume', 'makeup',
  ])
    w: ('Personal Care', null),
  // Wants
  for (final w in const ['movie', 'cinema', 'concert', 'game', 'games'])
    w: ('Entertainment', null),
  for (final w in const ['restaurant', 'lunch', 'dinner', 'takeaway', 'pizza'])
    w: ('Dining Out', null),
  for (final w in const ['clothes', 'shoes', 'dress', 'shirt', 'bag'])
    w: ('Shopping', null),
  for (final w in const ['gift', 'birthday', 'wedding', 'church', 'tithe'])
    w: ('Gifts & Giving', null),
};

/// Best-guess expense category id for an item name, or null.
String? guessCategoryId(String itemName, List<CategoryItem> expenseCategories) {
  final name = itemName.toLowerCase();
  final words = name.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);

  // 1. The user's own categories and subcategories, by name.
  CategoryItem? byName;
  for (final c in expenseCategories) {
    final cn = c.name.toLowerCase();
    // Whole words only, so "watermelon" is not mistaken for "Water".
    if (RegExp(r'\b' + RegExp.escape(cn) + r'\b').hasMatch(name)) {
      // Prefer the more specific subcategory.
      if (byName == null || c.parentId != null) byName = c;
    }
  }
  if (byName != null) return byName.id;

  // 2. Common words.
  for (final w in words) {
    final hit = _keywords[w];
    if (hit == null) continue;
    final parent = expenseCategories
        .where((c) => c.parentId == null && c.name == hit.$1)
        .firstOrNull;
    if (parent == null) continue;
    if (hit.$2 != null) {
      final sub = expenseCategories
          .where((c) => c.parentId == parent.id && c.name == hit.$2)
          .firstOrNull;
      if (sub != null) return sub.id;
    }
    return parent.id;
  }
  return null;
}

// ============================================================================
// REPOSITORY
// ============================================================================

class PlannedRepository {
  PlannedRepository(this._db);

  final AppDatabase _db;

  Future<List<CategoryItem>> _expenseCategories() => (_db.select(_db.categories)
        ..where(
          (c) =>
              c.kind.equalsValue(CategoryKind.expense) &
              c.isArchived.equals(false),
        ))
      .get();

  /// Adds items, guessing a category for each.
  Future<void> addAll(DateTime month, List<DraftItem> drafts) async {
    if (drafts.isEmpty) return;
    final cats = await _expenseCategories();
    final existing = await (_db.select(_db.plannedExpenses)
          ..where((p) => p.forMonth.equals(month)))
        .get();
    var order = existing.length;
    await _db.batch((b) {
      b.insertAll(_db.plannedExpenses, [
        for (final d in drafts)
          PlannedExpensesCompanion.insert(
            name: d.name,
            amountMinor: Value(d.amountMinor),
            categoryId: Value(guessCategoryId(d.name, cats)),
            forMonth: month,
            sortOrder: Value(order++),
          ),
      ]);
    });
  }

  Future<void> update(PlannedExpense item) => _db
      .update(_db.plannedExpenses)
      .replace(item.copyWith(updatedAt: DateTime.now()));

  Future<void> delete(String id) =>
      (_db.delete(_db.plannedExpenses)..where((p) => p.id.equals(id))).go();

  Future<void> restore(PlannedExpense item) =>
      _db.into(_db.plannedExpenses).insert(item);

  /// Records the purchase as a real expense and ticks the item off.
  Future<void> markDone(
    PlannedExpense item,
    int amountMinor,
    PaymentMethod? method,
  ) =>
      _db.transaction(() async {
        final txId = const Uuid().v4();
        await _db.into(_db.transactions).insert(
              TransactionsCompanion.insert(
                id: Value(txId),
                kind: TransactionKind.expense,
                amountMinor: amountMinor,
                currency: kDefaultCurrency,
                occurredAt: DateTime.now(),
                categoryId: Value(item.categoryId),
                paymentMethod: Value(method),
                note: Value(item.name),
              ),
            );
        await update(
          item.copyWith(
            isDone: true,
            amountMinor: Value(amountMinor),
            transactionId: Value(txId),
          ),
        );
      });

  /// Un-ticks the item with [id] (used by Undo, after the list has changed).
  Future<void> markUndoneById(String id) async {
    final item = await (_db.select(_db.plannedExpenses)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    if (item != null && item.isDone) await markUndone(item);
  }

  /// Un-ticks an item and removes the expense it created.
  Future<void> markUndone(PlannedExpense item) => _db.transaction(() async {
        final txId = item.transactionId;
        if (txId != null) {
          await (_db.delete(_db.transactions)..where((t) => t.id.equals(txId)))
              .go();
        }
        await update(item.copyWith(isDone: false, transactionId: const Value(null)));
      });
}

final plannedRepositoryProvider = Provider<PlannedRepository>(
  (ref) => PlannedRepository(ref.watch(appDatabaseProvider)),
);
