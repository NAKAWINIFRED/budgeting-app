import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/watch_tables.dart';

extension InvestmentTypeLabels on InvestmentType {
  String get label => switch (this) {
        InvestmentType.stocks => 'Stocks / shares',
        InvestmentType.fund => 'Fund / unit trust',
        InvestmentType.bonds => 'Bonds / treasury',
        InvestmentType.crypto => 'Crypto',
        InvestmentType.realEstate => 'Property / land',
        InvestmentType.business => 'Business',
        InvestmentType.pension => 'Pension',
        InvestmentType.other => 'Other',
      };

  String get iconKey => switch (this) {
        InvestmentType.stocks => 'trending_up',
        InvestmentType.fund => 'account_balance',
        InvestmentType.bonds => 'account_balance',
        InvestmentType.crypto => 'sell',
        InvestmentType.realEstate => 'home',
        InvestmentType.business => 'storefront',
        InvestmentType.pension => 'savings',
        InvestmentType.other => 'more_horiz',
      };
}

class InvestmentProgress {
  InvestmentProgress({
    required this.goal,
    required this.contributedMinor,
    required this.currentValueMinor,
    required this.startedOn,
    required this.valuations,
  });

  final SavingsGoal goal;

  /// Money put in minus money taken out.
  final int contributedMinor;

  /// Latest value update, plus anything put in or taken out since then.
  final int currentValueMinor;
  final DateTime startedOn;

  /// Value updates, oldest first.
  final List<InvestmentValuation> valuations;

  int get gainMinor => currentValueMinor - contributedMinor;
  double get gainPercent =>
      contributedMinor <= 0 ? 0 : gainMinor / contributedMinor;
  DateTime? get lastUpdated => valuations.isEmpty ? null : valuations.last.valuedOn;
}

class InvestmentsOverview {
  InvestmentsOverview(this.items);

  final List<InvestmentProgress> items;

  int get contributedMinor => items.fold(0, (s, i) => s + i.contributedMinor);
  int get valueMinor => items.fold(0, (s, i) => s + i.currentValueMinor);
  int get gainMinor => valueMinor - contributedMinor;
  double get gainPercent =>
      contributedMinor <= 0 ? 0 : gainMinor / contributedMinor;

  InvestmentProgress? byId(String id) =>
      items.where((i) => i.goal.id == id).firstOrNull;
}

final investmentsOverviewProvider = StreamProvider<InvestmentsOverview>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(
    db,
    [db.savingsGoals, db.transactions, db.investmentValuations],
    () async {
      final goals = await (db.select(db.savingsGoals)
            ..where((g) => g.isInvestment.equals(true) & g.isArchived.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
          .get();
      if (goals.isEmpty) return InvestmentsOverview([]);

      final ids = [for (final g in goals) g.id];
      final txs = await (db.select(db.transactions)
            ..where((t) => t.savingsGoalId.isIn(ids)))
          .get();
      final valuations = await (db.select(db.investmentValuations)
            ..where((v) => v.goalId.isIn(ids))
            ..orderBy([
              (v) => OrderingTerm.asc(v.valuedOn),
              (v) => OrderingTerm.asc(v.createdAt),
            ]))
          .get();

      return InvestmentsOverview([
        for (final g in goals) _progressFor(g, txs, valuations),
      ]);
    },
  );
});

InvestmentProgress _progressFor(
  SavingsGoal goal,
  List<MoneyTransaction> allTxs,
  List<InvestmentValuation> allValuations,
) {
  final txs = allTxs.where((t) => t.savingsGoalId == goal.id);
  final valuations =
      allValuations.where((v) => v.goalId == goal.id).toList();

  int signed(MoneyTransaction t) => switch (t.kind) {
        TransactionKind.savingsDeposit => t.amountMinor,
        TransactionKind.savingsWithdrawal => -t.amountMinor,
        _ => 0,
      };

  final contributed =
      goal.startingAmountMinor + txs.fold<int>(0, (s, t) => s + signed(t));

  int current;
  if (valuations.isEmpty) {
    current = contributed;
  } else {
    final latest = valuations.last;
    final since = txs
        .where((t) => t.occurredAt.isAfter(latest.valuedOn))
        .fold<int>(0, (s, t) => s + signed(t));
    current = latest.valueMinor + since;
  }

  return InvestmentProgress(
    goal: goal,
    contributedMinor: contributed,
    currentValueMinor: current,
    startedOn: valuations.isEmpty ? goal.createdAt : valuations.first.valuedOn,
    valuations: valuations,
  );
}

class InvestmentsRepository {
  InvestmentsRepository(this._db);

  final AppDatabase _db;

  /// [putInMinor]: money invested so far. [worthNowMinor]: its value today.
  Future<String> add({
    required String name,
    required InvestmentType type,
    required String currency,
    required int putInMinor,
    required int worthNowMinor,
    required DateTime startedOn,
  }) async {
    final id = const Uuid().v4();
    await _db.transaction(() async {
      await _db.into(_db.savingsGoals).insert(
            SavingsGoalsCompanion.insert(
              id: Value(id),
              name: name,
              term: SavingsTerm.longTerm,
              currency: currency,
              iconKey: Value(type.iconKey),
              startingAmountMinor: Value(putInMinor),
              isInvestment: const Value(true),
              investmentType: Value(type),
            ),
          );
      // Starting point: worth what was put in.
      await addValuation(id, putInMinor, startedOn);
      if (worthNowMinor != putInMinor) {
        await addValuation(id, worthNowMinor, DateTime.now());
      }
    });
    return id;
  }

  Future<void> addValuation(String goalId, int valueMinor, DateTime valuedOn) =>
      _db.into(_db.investmentValuations).insert(
            InvestmentValuationsCompanion.insert(
              goalId: goalId,
              valueMinor: valueMinor,
              valuedOn: valuedOn,
            ),
          );

  Future<void> deleteValuation(String id) =>
      (_db.delete(_db.investmentValuations)..where((v) => v.id.equals(id))).go();
}

final investmentsRepositoryProvider = Provider<InvestmentsRepository>(
  (ref) => InvestmentsRepository(ref.watch(appDatabaseProvider)),
);
