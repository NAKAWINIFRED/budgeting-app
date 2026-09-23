import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import 'subscription_sheet.dart';
import 'subscriptions_providers.dart';

/// Records a payment for [s], moves its due date on, and offers Undo.
Future<void> markSubscriptionPaid(
  BuildContext context,
  WidgetRef ref,
  Subscription s,
) async {
  final repo = ref.read(subscriptionsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final txId = await repo.markPaid(s);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '${s.name} paid. Next due '
        '${DateFormat.MMMd().format(s.frequency.next(s.nextDueDate))}.',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => repo.undoPaid(s, txId),
      ),
    ),
  );
}

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    final text = Theme.of(context).textTheme;
    const currency = kDefaultCurrency;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions & bills')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSubscriptionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
        shape: const StadiumBorder(),
      ),
      body: subs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load subscriptions.\n$e')),
        data: (list) {
          final monthly = list.fold<int>(
            0,
            (sum, s) => sum + s.frequency.monthlyMinor(s.amountMinor),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
            children: [
              if (list.isEmpty) ...[
                Text(
                  'Add the things you pay again and again: rent, phone, '
                  'internet, streaming, school fees, insurance. Tidewise '
                  'will remind you before each one is due.',
                  style: text.bodyMedium?.copyWith(color: AppColors.mist),
                ),
              ] else ...[
                Text(
                  'All together, about',
                  style: text.bodyMedium?.copyWith(color: AppColors.mist),
                ),
                Text(
                  '${Money.format(monthly, currency)} a month',
                  style: AppText.amount(30, weight: FontWeight.w800, color: AppColors.expense),
                ),
                Text(
                  'That is ${Money.format(monthly * 12, currency)} a year. '
                  'Worth checking now and then for anything you no longer use.',
                  style: text.bodySmall?.copyWith(color: AppColors.mist),
                ),
                const SizedBox(height: 20),
                for (final s in list) SubscriptionTile(subscription: s),
              ],
            ],
          );
        },
      ),
    );
  }
}

class SubscriptionTile extends ConsumerWidget {
  const SubscriptionTile({super.key, required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
    final text = Theme.of(context).textTheme;
    const currency = kDefaultCurrency;
    final dueColor = s.isOverdue
        ? AppColors.expense
        : s.needsAttention
            ? AppColors.amber
            : AppColors.mist;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: s.needsAttention ? dueColor : AppColors.line,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showSubscriptionSheet(context, existing: s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.shallows,
                    child: Icon(
                      Icons.autorenew_rounded,
                      size: 20,
                      color: AppColors.deepWater,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          s.purpose ?? s.frequency.label,
                          style: text.bodySmall?.copyWith(color: AppColors.mist),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Money.format(s.amountMinor, currency),
                        style: AppText.amount(16, color: AppColors.expense),
                      ),
                      Text(
                        s.frequency.per,
                        style: text.bodySmall?.copyWith(color: AppColors.mist),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 16, color: dueColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.dueLabel} (${DateFormat.MMMd().format(s.nextDueDate)})',
                      style: text.bodySmall?.copyWith(
                        color: dueColor,
                        fontWeight: s.needsAttention ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => markSubscriptionPaid(context, ref, s),
                    child: const Text('Mark as paid'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
