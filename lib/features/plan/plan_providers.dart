import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';

class StrategyOption {
  StrategyOption(this.strategy, this.buckets);

  final BudgetStrategy strategy;
  final List<BudgetBucket> buckets;

  /// e.g. "50% Needs, 30% Wants, 20% Savings & Debt"
  String get splitSummary => buckets
      .map((b) => '${(b.basisPoints / 100).round()}% ${b.name}')
      .join(', ');
}

/// Every strategy (presets and, later, custom ones) with its buckets.
final strategyOptionsProvider = StreamProvider<List<StrategyOption>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(db, [db.budgetStrategies, db.budgetBuckets], () async {
    final strategies = await db.select(db.budgetStrategies).get();
    final buckets = await (db.select(db.budgetBuckets)
          ..orderBy([(b) => OrderingTerm.asc(b.sortOrder)]))
        .get();
    return [
      for (final s in strategies)
        StrategyOption(s, buckets.where((b) => b.strategyId == s.id).toList()),
    ];
  });
});

class StrategiesRepository {
  StrategiesRepository(this._db);

  final AppDatabase _db;

  /// Makes [id] the one active strategy.
  Future<void> setActive(String id) => _db.transaction(() async {
        await _db
            .update(_db.budgetStrategies)
            .write(const BudgetStrategiesCompanion(isActive: Value(false)));
        await (_db.update(_db.budgetStrategies)..where((s) => s.id.equals(id)))
            .write(const BudgetStrategiesCompanion(isActive: Value(true)));
      });
}

final strategiesRepositoryProvider = Provider<StrategiesRepository>(
  (ref) => StrategiesRepository(ref.watch(appDatabaseProvider)),
);
