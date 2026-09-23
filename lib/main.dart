import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/money.dart';
import 'data/database.dart';
import 'data/database_provider.dart';

void main() {
  runApp(const ProviderScope(child: TidewiseApp()));
}

class TidewiseApp extends StatelessWidget {
  const TidewiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tidewise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F766E),
        useMaterial3: true,
      ),
      home: const SetupCheckScreen(),
    );
  }
}

// ----------------------------------------------------------------------------
// TEMPORARY screen: proves the database is created and seeded correctly.
// We'll replace it with the real dashboard next.
// ----------------------------------------------------------------------------

class StrategyPreview {
  StrategyPreview(this.strategy, this.buckets);

  final BudgetStrategy strategy;
  final List<BudgetBucket> buckets;
}

final categoryCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.select(db.categories).get();
  return rows.length;
});

final strategiesPreviewProvider =
    FutureProvider<List<StrategyPreview>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final strategies = await db.select(db.budgetStrategies).get();

  return [
    for (final s in strategies)
      StrategyPreview(
        s,
        await (db.select(db.budgetBuckets)
              ..where((b) => b.strategyId.equals(s.id))
              ..orderBy([(b) => OrderingTerm.asc(b.sortOrder)]))
            .get(),
      ),
  ];
});

class SetupCheckScreen extends ConsumerWidget {
  const SetupCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryCount = ref.watch(categoryCountProvider);
    final strategies = ref.watch(strategiesPreviewProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tidewise · Setup check')),
      body: strategies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Database error:\n$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Categories ready: ${categoryCount.value ?? '...'}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Money check: ${Money.format(Money.toMinor(1234.5, 'USD'), 'USD')}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final preview in list)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview.strategy.name,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          if (preview.strategy.isActive)
                            const Chip(label: Text('Active')),
                        ],
                      ),
                      if (preview.strategy.description != null)
                        Text(preview.strategy.description!),
                      const SizedBox(height: 8),
                      for (final bucket in preview.buckets)
                        Text(
                          '${(bucket.basisPoints / 100).toStringAsFixed(0)}%  '
                          '${bucket.name}',
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}