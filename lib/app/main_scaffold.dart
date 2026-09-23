import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/database.dart';
import '../features/transactions/quick_add_sheet.dart';
import 'app_drawer.dart';

/// The frame every main page uses: a title bar with the menu button, the
/// side menu, and the + button (which opens ready for this page's kind).
class MainScaffold extends StatelessWidget {
  const MainScaffold({
    super.key,
    required this.title,
    required this.body,
    this.addKind = TransactionKind.expense,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final TransactionKind addKind;
  final List<Widget>? actions;

  /// Replaces the default + button when a page needs its own.
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final isHome = GoRouterState.of(context).uri.path == '/';

    return PopScope(
      // Back goes to the previous page if there is one, otherwise home.
      canPop: isHome || context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        drawer: const AppDrawer(),
        floatingActionButton: floatingActionButton ??
            FloatingActionButton(
              tooltip: 'Add',
              onPressed: () => showQuickAddSheet(context, kind: addKind),
              child: const Icon(Icons.add_rounded, size: 28),
            ),
        body: body,
      ),
    );
  }
}
