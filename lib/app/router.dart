import 'package:go_router/go_router.dart';

import '../features/activity/activity_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/plan/plan_screen.dart';
import '../data/database.dart';
import 'app_shell.dart';

/// All app navigation lives here. Each tab keeps its own history, so
/// switching tabs doesn't lose your place.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Full-screen pages that open on top of the tabs.
    GoRoute(
      path: '/categories',
      builder: (context, state) => CategoriesScreen(
        initialKind: state.uri.queryParameters['kind'] == 'income'
            ? CategoryKind.income
            : CategoryKind.expense,
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/activity',
              builder: (context, state) => const ActivityScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/goals',
              builder: (context, state) => const GoalsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
