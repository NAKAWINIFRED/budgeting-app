import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'database_provider.dart';

/// Live lists used by pickers across the app. They update automatically
/// when something is added, renamed or archived.

final categoriesProvider =
    StreamProvider.family<List<CategoryItem>, CategoryKind>((ref, kind) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.categories)
        ..where((c) => c.kind.equalsValue(kind) & c.isArchived.equals(false))
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .watch();
});

final activeGoalsProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.savingsGoals)
        ..where((g) => g.isArchived.equals(false))
        ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
      .watch();
});

final activeDebtsProvider = StreamProvider<List<Debt>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.debts)
        ..where((d) => d.isClosed.equals(false))
        ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
      .watch();
});
