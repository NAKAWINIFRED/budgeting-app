import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/database.dart';

/// One consistent color per kind of money movement, used everywhere:
/// income blue, expenses red, savings teal, debt payments navy.
Color amountColorFor(TransactionKind kind) => switch (kind) {
      TransactionKind.income => AppColors.lagoon,
      TransactionKind.expense => AppColors.expense,
      TransactionKind.savingsDeposit => AppColors.tide,
      TransactionKind.savingsWithdrawal => AppColors.lagoon,
      TransactionKind.debtPayment => AppColors.deepWater,
    };

extension PaymentMethodLabels on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.mobileMoney => 'Mobile money',
        PaymentMethod.bank => 'Bank',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };

  IconData get icon => switch (this) {
        PaymentMethod.cash => Icons.money_rounded,
        PaymentMethod.mobileMoney => Icons.smartphone_rounded,
        PaymentMethod.bank => Icons.account_balance_rounded,
        PaymentMethod.card => Icons.credit_card_rounded,
        PaymentMethod.other => Icons.more_horiz_rounded,
      };
}
