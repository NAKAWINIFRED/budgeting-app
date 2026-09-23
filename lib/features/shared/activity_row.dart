import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../core/money_kinds.dart';
import '../dashboard/dashboard_providers.dart';

/// One transaction in a list: icon, title, subtitle, signed amount.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.item,
    required this.currency,
    this.subtitle,
    this.onTap,
  });

  final ActivityItem item;
  final String currency;

  /// Defaults to the date and payment method, e.g. "Sep 21, Cash".
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sign = item.isIncoming ? '+' : '\u2212';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.shallows,
              child: Icon(
                iconFor(item.iconKey),
                size: 20,
                color: AppColors.deepWater,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle ??
                        [
                          DateFormat.MMMd().format(item.tx.occurredAt),
                          if (item.tx.paymentMethod != null)
                            item.tx.paymentMethod!.label,
                        ].join(', '),
                    style: text.bodySmall?.copyWith(color: AppColors.mist),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign${Money.format(item.tx.amountMinor, currency)}',
              style: AppText.amount(
                15,
                color: amountColorFor(item.tx.kind),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
