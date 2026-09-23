import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../dashboard/dashboard_providers.dart' show currentMonthRange;

// ============================================================================
// MODELS
// ============================================================================

class DebtProgress {
  DebtProgress({
    required this.debt,
    required this.paidTrackedMinor,
    required this.paidThisMonthMinor,
  });

  final Debt debt;

  /// Payments recorded in Tidewise.
  final int paidTrackedMinor;
  final int paidThisMonthMinor;

  int get totalMinor => debt.originalAmountMinor;
  int get paidMinor => debt.paidBeforeTrackingMinor + paidTrackedMinor;
  int get remainingMinor => math.max(0, totalMinor - paidMinor);
  bool get isPaidOff => totalMinor > 0 && remainingMinor == 0;

  /// 0.0 (nothing paid) to 1.0 (paid off).
  double get progress =>
      totalMinor <= 0 ? 0 : (paidMinor / totalMinor).clamp(0.0, 1.0).toDouble();

  /// Rough months left at the user's monthly payment (ignores interest).
  int? get monthsLeft {
    final monthly = debt.minimumPaymentMinor;
    if (monthly == null || monthly <= 0 || isPaidOff) return null;
    return (remainingMinor / monthly).ceil();
  }
}

class DebtOverview {
  DebtOverview(this.debts);

  final List<DebtProgress> debts;

  List<DebtProgress> get active =>
      debts.where((d) => !d.debt.isClosed).toList();

  int get totalMinor => active.fold(0, (sum, d) => sum + d.totalMinor);
  int get remainingMinor => active.fold(0, (sum, d) => sum + d.remainingMinor);
  int get paidMinor => totalMinor - remainingMinor;
  int get paidThisMonthMinor =>
      active.fold(0, (sum, d) => sum + d.paidThisMonthMinor);

  double get progress => totalMinor <= 0 ? 0 : paidMinor / totalMinor;

  DebtProgress? byId(String id) =>
      debts.where((d) => d.debt.id == id).firstOrNull;
}

// ============================================================================
// PROVIDERS
// Re-calculates whenever a debt or any transaction changes.
// ============================================================================

final debtOverviewProvider = StreamProvider<DebtOverview>(
  (ref) => _watchDebts(ref.watch(appDatabaseProvider)),
);

Stream<DebtOverview> _watchDebts(AppDatabase db) async* {
  yield await _loadDebts(db);
  final changes = db.tableUpdates(
    TableUpdateQuery.onAllTables([db.debts, db.transactions]),
  );
  await for (final _ in changes) {
    yield await _loadDebts(db);
  }
}

Future<DebtOverview> _loadDebts(AppDatabase db) async {
  final debts = await (db.select(db.debts)
        ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
      .get();

  final payments = await (db.select(db.transactions)
        ..where((t) => t.kind.equalsValue(TransactionKind.debtPayment)))
      .get();

  final (start, end) = currentMonthRange();
  final paidTotal = <String, int>{};
  final paidMonth = <String, int>{};

  for (final p in payments) {
    final id = p.debtId;
    if (id == null) continue;
    paidTotal[id] = (paidTotal[id] ?? 0) + p.amountMinor;
    if (!p.occurredAt.isBefore(start) && p.occurredAt.isBefore(end)) {
      paidMonth[id] = (paidMonth[id] ?? 0) + p.amountMinor;
    }
  }

  return DebtOverview([
    for (final d in debts)
      DebtProgress(
        debt: d,
        paidTrackedMinor: paidTotal[d.id] ?? 0,
        paidThisMonthMinor: paidMonth[d.id] ?? 0,
      ),
  ]);
}

// ============================================================================
// REPOSITORY
// ============================================================================

class DebtsRepository {
  DebtsRepository(this._db);

  final AppDatabase _db;

  /// [owedNowMinor] is what's left today. If [originalMinor] (what was
  /// borrowed) is bigger, the difference counts as already paid.
  Future<String> add({
    required String name,
    required DebtType type,
    required int owedNowMinor,
    required String currency,
    String? lender,
    int? originalMinor,
    int? monthlyPaymentMinor,
  }) async {
    final original = math.max(originalMinor ?? owedNowMinor, owedNowMinor);
    final id = const Uuid().v4();
    await _db.into(_db.debts).insert(
          DebtsCompanion.insert(
            id: Value(id),
            name: name,
            debtType: type,
            lender: Value(lender),
            originalAmountMinor: original,
            paidBeforeTrackingMinor: Value(original - owedNowMinor),
            currency: currency,
            minimumPaymentMinor: Value(monthlyPaymentMinor),
          ),
        );
    return id;
  }
}

final debtsRepositoryProvider = Provider<DebtsRepository>(
  (ref) => DebtsRepository(ref.watch(appDatabaseProvider)),
);
