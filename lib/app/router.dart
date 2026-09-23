import 'package:go_router/go_router.dart';

import '../features/activity/activity_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/shared/coming_soon_screen.dart';
import 'app_shell.dart';

/// All app navigation lives here. Each tab keeps its own history, so
/// switching tabs doesn't lose your place.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
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
              builder: (context, state) => const ComingSoonScreen(
                title: 'Plan',
                message:
                    'Choose and customise your budget strategy here, like 50/30/20 or 50/15/5/30.',
              ),
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
