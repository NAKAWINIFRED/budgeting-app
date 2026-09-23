import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/category_icons.dart';
import '../../data/database.dart';
import 'categories_repository.dart';
import 'category_sheet.dart';

/// Add, rename and remove categories and subcategories.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key, this.initialKind = CategoryKind.expense});

  final CategoryKind initialKind;

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  late CategoryKind _kind = widget.initialKind;

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider(_kind));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategorySheet(context, kind: _kind),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
        shape: const StadiumBorder(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
        children: [
          SegmentedButton<CategoryKind>(
            segments: const [
              ButtonSegment(value: CategoryKind.expense, label: Text('Expenses')),
              ButtonSegment(value: CategoryKind.income, label: Text('Income')),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap a category or subcategory to rename it, change its icon or '
            'remove it.',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 12),
          tree.when(
            loading: () => const SizedBox(height: 80),
            error: (e, _) => Text('Could not load categories.\n$e'),
            data: (nodes) => Column(
              children: [
                for (final node in nodes) _CategoryCard(node: node, kind: _kind),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.node, required this.kind});

  final CategoryNode node;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = node.category;
    final tagLabel = switch (c.budgetTag) {
      BudgetTag.essentials => 'Need',
      BudgetTag.wants => 'Want',
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => showCategorySheet(context, kind: kind, existing: c),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.shallows,
                    child: Icon(
                      iconFor(c.iconKey),
                      size: 20,
                      color: AppColors.deepWater,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.name,
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (tagLabel != null)
                    Text(
                      tagLabel,
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.mist),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(66, 0, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sub in node.children)
                  ActionChip(
                    avatar: Icon(iconFor(sub.iconKey), size: 16),
                    label: Text(sub.name),
                    backgroundColor: AppColors.foam,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    onPressed: () => showCategorySheet(
                      context,
                      kind: kind,
                      parent: c,
                      existing: sub,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16, color: AppColors.tide),
                  label: const Text('Subcategory'),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.tide),
                  shape: const StadiumBorder(),
                  onPressed: () => showCategorySheet(context, kind: kind, parent: c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
