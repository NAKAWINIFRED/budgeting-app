import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/money.dart';
import '../data/database.dart';

/// Fills the current month with realistic test data so we can see the
/// dashboard working. Only reachable from a button in debug builds.
Future<void> insertSampleData(AppDatabase db) async {
  const currency = kDefaultCurrency;
  const uuid = Uuid();
  final now = DateTime.now();

  // A date this month, never in the future.
  DateTime day(int d) => DateTime(now.year, now.month, d > now.day ? now.day : d, 12);

  final categories = await db.select(db.categories).get();
  String cat(String name) => categories.firstWhere((c) => c.name == name).id;

  final emergencyFundId = uuid.v4();
  final retirementId = uuid.v4();
  final carLoanId = uuid.v4();

  TransactionsCompanion tx(
    TransactionKind kind,
    num amount,
    DateTime at, {
    String? categoryId,
    String? goalId,
    String? debtId,
  }) {
    return TransactionsCompanion.insert(
      kind: kind,
      amountMinor: Money.toMinor(amount, currency),
      currency: currency,
      occurredAt: at,
      categoryId: Value(categoryId),
      savingsGoalId: Value(goalId),
      debtId: Value(debtId),
    );
  }

  await db.batch((b) {
    b.insertAll(db.savingsGoals, [
      SavingsGoalsCompanion.insert(
        id: Value(emergencyFundId),
        name: 'Emergency Fund',
        term: SavingsTerm.shortTerm,
        currency: currency,
        targetAmountMinor: Value(Money.toMinor(1500, currency)),
      ),
      SavingsGoalsCompanion.insert(
        id: Value(retirementId),
        name: 'Retirement',
        term: SavingsTerm.longTerm,
        currency: currency,
      ),
    ]);

    b.insert(
      db.debts,
      DebtsCompanion.insert(
        id: Value(carLoanId),
        name: 'Car Loan',
        debtType: DebtType.carLoan,
        lender: const Value('City Bank'),
        originalAmountMinor: Money.toMinor(8000, currency),
        currency: currency,
        minimumPaymentMinor: Value(Money.toMinor(250, currency)),
      ),
    );

    b.insertAll(db.transactions, [
      tx(TransactionKind.income, 2400, day(1), categoryId: cat('Salary')),
      tx(TransactionKind.income, 350, day(5), categoryId: cat('Freelance & Gigs')),
      tx(TransactionKind.expense, 850, day(2), categoryId: cat('Housing & Rent')),
      tx(TransactionKind.expense, 140, day(3), categoryId: cat('Groceries')),
      tx(TransactionKind.expense, 85, day(9), categoryId: cat('Groceries')),
      tx(TransactionKind.expense, 60, day(4), categoryId: cat('Transport')),
      tx(TransactionKind.expense, 75, day(6), categoryId: cat('Utilities')),
      tx(TransactionKind.expense, 25, day(6), categoryId: cat('Phone & Internet')),
      tx(TransactionKind.expense, 48, day(8), categoryId: cat('Dining Out')),
      tx(TransactionKind.expense, 30, day(10), categoryId: cat('Entertainment')),
      tx(TransactionKind.expense, 65, day(11), categoryId: cat('Shopping')),
      tx(TransactionKind.savingsDeposit, 150, day(2), goalId: emergencyFundId),
      tx(TransactionKind.savingsDeposit, 300, day(2), goalId: retirementId),
      tx(TransactionKind.debtPayment, 250, day(7), debtId: carLoanId),
    ]);
  });
}
