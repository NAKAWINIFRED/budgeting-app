import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

// ============================================================================
// ENUMS
// Stored in the database as text (their .name), so reordering values is safe.
// Never RENAME a value once the app is published without a migration.
// ============================================================================

enum TransactionKind {
  income,
  expense,
  savingsDeposit,
  savingsWithdrawal,
  debtPayment,
}

enum CategoryKind { income, expense }

enum IncomeFrequency { daily, weekly, biweekly, semimonthly, monthly, irregular }

enum DebtType {
  carLoan,
  studentLoan,
  mortgage,
  creditCard,
  personalLoan,
  familyOrFriend,
  mobileLoan,
  medical,
  business,
  other,
}

enum SavingsTerm { shortTerm, longTerm }

/// What a category, savings goal or debt "counts as" when a budget
/// strategy splits income into buckets (e.g. 50% essentials).
enum BudgetTag { essentials, wants, longTermSavings, shortTermSavings, debt }

// ============================================================================
// SHARED COLUMNS
// Every table gets a UUID id plus timestamps. UUIDs (instead of 1, 2, 3...)
// make cloud sync with Supabase much easier later.
// ============================================================================

mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// ============================================================================
// TABLES
// All money is stored as whole integers in the currency's smallest unit
// (cents for USD, whole francs for RWF). Never use doubles for money.
// ============================================================================

@DataClassName('CategoryItem')
class Categories extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get iconKey => text()();
  // Only expense categories have a budget tag.
  TextColumn get budgetTag => textEnum<BudgetTag>().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('IncomeSource')
class IncomeSources extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get frequency => textEnum<IncomeFrequency>()();
  // Optional: irregular earners may not know this.
  IntColumn get expectedAmountMinor => integer().nullable()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One table for every money movement: income, spending, savings, debt
/// payments. This keeps monthly summaries simple and fast.
@DataClassName('MoneyTransaction')
class Transactions extends Table with SyncColumns {
  TextColumn get kind => textEnum<TransactionKind>()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();

  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get incomeSourceId =>
      text().nullable().references(IncomeSources, #id)();
  TextColumn get debtId => text().nullable().references(Debts, #id)();
  TextColumn get savingsGoalId =>
      text().nullable().references(SavingsGoals, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

/// The pieces of one expense, e.g. a grocery trip split into Eggs, Soap,
/// Milk, or a bills payment split into Electricity, Water, Wifi.
/// When a transaction has items, its amount is the sum of its items.
/// (Added in schema version 3.)
@DataClassName('TransactionItem')
class TransactionItems extends Table with SyncColumns {
  TextColumn get transactionId => text()
      .references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetStrategy')
class BudgetStrategies extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get description => text().nullable()();
  BoolColumn get isPreset => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A slice of a strategy, e.g. "Needs: 50%". Percentages are stored as
/// basis points: 10000 = 100%, 5000 = 50%, 1500 = 15%.
@DataClassName('BudgetBucket')
class BudgetBuckets extends Table with SyncColumns {
  TextColumn get strategyId => text().references(BudgetStrategies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get basisPoints => integer()();
  // Comma-separated BudgetTag names, e.g. "longTermSavings,shortTermSavings".
  TextColumn get tags => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Payments are Transactions with kind = debtPayment and this debt's id.
/// Remaining = originalAmountMinor - paidBeforeTrackingMinor - sum(payments).
@DataClassName('Debt')
class Debts extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get debtType => textEnum<DebtType>()();
  TextColumn get lender => text().nullable()();
  IntColumn get originalAmountMinor => integer()();
  // Amount already repaid before the user started tracking in Tidewise,
  // so their earlier progress still counts. (Added in schema version 2.)
  IntColumn get paidBeforeTrackingMinor =>
      integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  // Basis points again: 1250 = 12.5% interest per year.
  IntColumn get interestRateBasisPoints => integer().nullable()();
  IntColumn get minimumPaymentMinor => integer().nullable()();
  IntColumn get dueDayOfMonth => integer().nullable()();
  DateTimeColumn get startedOn => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Saved = startingAmountMinor + deposits - withdrawals (Transactions with
/// kind savingsDeposit / savingsWithdrawal and this goal's id).
@DataClassName('SavingsGoal')
class SavingsGoals extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get term => textEnum<SavingsTerm>()();
  IntColumn get targetAmountMinor => integer().nullable()();
  // Money already saved before tracking in Tidewise. (Schema version 4.)
  IntColumn get startingAmountMinor =>
      integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get iconKey => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
