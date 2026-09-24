import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

/// The side menu. Everything in Tidewise is one tap away from here.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final text = Theme.of(context).textTheme;

    Widget item(String label, IconData icon, String route, {double indent = 0}) {
      final selected = path == route;
      return Padding(
        padding: EdgeInsets.fromLTRB(12 + indent, 2, 12, 2),
        child: ListTile(
          dense: indent > 0,
          leading: Icon(
            icon,
            color: selected ? AppColors.deepWater : AppColors.mist,
            size: indent > 0 ? 20 : 24,
          ),
          title: Text(
            label,
            style: text.bodyLarge?.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: AppColors.deepWater,
            ),
          ),
          selected: selected,
          selectedTileColor: AppColors.shallows,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () {
            Navigator.of(context).pop(); // close the menu
            if (!selected) context.go(route);
          },
        ),
      );
    }

    Widget heading(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 16, 6),
          child: Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: AppColors.mist,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    final inExpenses = path.startsWith('/expenses');

    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: AppColors.deepWater,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.paddingOf(context).top + 24,
              24,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.waves_rounded, color: AppColors.shallows, size: 32),
                const SizedBox(height: 10),
                Text(
                  'Tidewise',
                  style: text.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Your money, in and out, calmly.',
                  style: text.bodyMedium?.copyWith(color: AppColors.shallows),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          item('Overview', Icons.dashboard_rounded, '/'),
          heading('Money in & out'),
          item('Income', Icons.south_west_rounded, '/income'),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExpansionTile(
                initiallyExpanded: inExpenses,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(
                  Icons.north_east_rounded,
                  color: inExpenses ? AppColors.deepWater : AppColors.mist,
                ),
                title: Text(
                  'Expenses',
                  style: text.bodyLarge?.copyWith(
                    fontWeight: inExpenses ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                childrenPadding: EdgeInsets.zero,
                children: [
                  item('Upcoming expenses', Icons.checklist_rounded, '/expenses/planned', indent: 12),
                  item('All expenses', Icons.pie_chart_outline_rounded, '/expenses', indent: 12),
                  item('Daily expenses', Icons.shopping_basket_outlined, '/expenses/daily', indent: 12),
                  item('Bills & housing', Icons.home_outlined, '/expenses/bills', indent: 12),
                  item('Subscriptions', Icons.autorenew_rounded, '/expenses/subscriptions', indent: 12),
                  item('Other expenses', Icons.more_horiz_rounded, '/expenses/other', indent: 12),
                ],
              ),
            ),
          ),
          item('Activity', Icons.receipt_long_rounded, '/activity'),
          heading('Growing'),
          item('Savings', Icons.savings_rounded, '/savings'),
          item('Investments', Icons.trending_up_rounded, '/investments'),
          heading('Paying off'),
          item('Debt', Icons.payments_rounded, '/debts'),
          heading('Planning'),
          item('Budget plan', Icons.donut_large_rounded, '/plan'),
          item('Categories', Icons.tune_rounded, '/categories'),
          const Divider(height: 24, indent: 24, endIndent: 24),
          item('Settings', Icons.settings_outlined, '/settings'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
