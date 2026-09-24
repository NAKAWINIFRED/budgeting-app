import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_config.dart';
import '../data/database.dart';
import '../features/activity/activity_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expenses/expenses_providers.dart';
import '../features/expenses/expenses_screens.dart';
import '../features/goals/goals_screen.dart';
import '../features/income/income_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/planned/planned_screen.dart';
import '../features/settings/settings_screen.dart';

/// Every page in the app. The side menu (app_drawer.dart) links to these.
final appRouter = GoRouter(
  initialLocation: '/',
  // First launch: show onboarding until it is finished.
  redirect: (context, state) {
    final onWelcome = state.uri.path == '/welcome';
    if (!AppConfig.onboardingDone && !onWelcome) return '/welcome';
    if (AppConfig.onboardingDone && onWelcome) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const OnboardingScreen(),
    ),
    _page('/', (_) => const DashboardScreen()),
    _page('/income', (_) => const IncomeScreen()),
    _page('/expenses', (_) => const ExpensesOverviewScreen()),
    _page(
      '/expenses/planned',
      (state) => PlannedScreen(
        startNextMonth: state.uri.queryParameters['month'] == 'next',
      ),
    ),
    _page(
      '/expenses/daily',
      (_) => const ExpenseSectionScreen(section: ExpenseSection.daily),
    ),
    _page(
      '/expenses/bills',
      (_) => const ExpenseSectionScreen(section: ExpenseSection.billsHousing),
    ),
    _page(
      '/expenses/subscriptions',
      (_) => const ExpenseSectionScreen(section: ExpenseSection.subscriptions),
    ),
    _page(
      '/expenses/other',
      (_) => const ExpenseSectionScreen(section: ExpenseSection.other),
    ),
    _page('/activity', (_) => const ActivityScreen()),
    _page('/savings', (_) => const SavingsScreen()),
    _page('/investments', (_) => const InvestmentsScreen()),
    _page('/debts', (_) => const DebtsScreen()),
    _page('/plan', (_) => const PlanScreen()),
    _page('/settings', (_) => const SettingsScreen()),
    _page(
      '/categories',
      (state) => CategoriesScreen(
        initialKind: state.uri.queryParameters['kind'] == 'income'
            ? CategoryKind.income
            : CategoryKind.expense,
      ),
    ),
    // Older links.
    GoRoute(path: '/subscriptions', redirect: (_, __) => '/expenses/subscriptions'),
    GoRoute(path: '/goals', redirect: (_, __) => '/savings'),
  ],
);

GoRoute _page(String path, Widget Function(GoRouterState state) build) {
  return GoRoute(
    path: path,
    // A quick fade between pages feels calmer than a slide from the menu.
    pageBuilder: (context, state) => CustomTransitionPage(
      key: state.pageKey,
      child: build(state),
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
